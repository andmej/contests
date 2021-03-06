module LiveArchive
  class SubmissionFetcher
    DOMAIN = "http://livearchive.onlinejudge.org/"
    SUBMISSIONS_URL = DOMAIN + "index.php?option=com_onlinejudge&Itemid=19"
  
    def daemon
      puts "#{timestamp} Starting daemon to fetch submissions..."
      STDERR.puts "#{timestamp} Starting daemon to fetch submissions..."
      while true
        begin
          fetch
          puts "#{timestamp} Sleeping 60 seconds before retrying..."
          sleep 60
        rescue => e
          puts "#{timestamp} Holy Macaroni! And exception was raised: #{e}"
          puts "#{timestamp} Retrying in 5 seconds, anyway."
          sleep 5
        end
      end
    end
  
    def timestamp
      "[#{Time.now}]"
    end
  
    def fetch
      bot = Mechanize.new
    
      puts "Fetching submissions from Live Archive..."
      page = bot.get(SUBMISSIONS_URL)

      table_with_submissions = page.search("html body table tr td.main table tr td.maincontent table")
    
      table_with_submissions.search("tr").each do |tr|
        next if tr.attr("class") =~ /sectiontableheader/ # Header
      
        cells = tr.search("td")
      
        attributes = {
          :judge_identifier => cells[0].content,
          :number           => cells[1].search("a").first.content,
          :problem_name     => cells[2].search("a").first.content,
          :user_name        => cells[3].search("a").first.content,
          :user_url         => cells[3].search("a").first.attr("href"),
          :verdict          => cells[4].content,
          :language         => cells[5].content,
          :run_time         => cells[6].content,
          :submitted_at     => cells[7].content,
        }
      
        try_to_create_submission(attributes)
      end
    end
  
    protected
  
    def try_to_create_submission(attr)
      puts ""
      puts "Trying to create submission with attributes: #{attr.inspect}..."
    
      if ["Sent to judge", "Compiling", "In judge queue", "Running", "Linking"].include?(attr[:verdict])
        puts "Discarding because verdict is '#{attr[:verdict]}'."
        return
      end
    
      submission = Submission.find_by_judge_identifier(attr[:judge_identifier])
      if submission.present?
        puts "Discarding because it's a duplicate."
        return
      end
    
      problem = Problem.order("created_at desc").find_by_number(attr[:number])
      if problem.blank?
        puts "Discarding because there's no problem with number '#{attr[:number]}'."
        return
      end
        
      if attr[:verdict].blank?
        puts "Discarding because the verdict is blank"
        return
      end
        
      attr[:submitted_at] = Time.parse(attr[:submitted_at] + " GMT")
    
      unless problem.belongs_to_at_least_one_running_contest?
        puts "Discarding because problem #{attr[:number]} - #{attr[:problem_name]} is not being used in any currently running contest."
        return
      end
    
      username = extract_username(attr[:user_url])
      puts "Username is #{username}..."
    
      team = Team.find_by_username(username)
      if team.blank?
        puts "Discarding because there's no team with username '#{username}'."
        return
      end    
    
      problem.contests.each do |contest|
        if !contest.within_contest_time_lapse?(attr[:submitted_at])
          puts "Discarding because the submission is outside the contest time lapse. Contest time lapse is [#{contest.start_date}, #{contest.end_date}] but submission time is #{attr[:submitted_at]}."
          next
        end
        submission = contest.submissions.create!(:problem => problem, :team => team, :verdict => attr[:verdict],
                                                 :language => attr[:language], :run_time => attr[:run_time],
                                                 :submitted_at => attr[:submitted_at], :judge_identifier => attr[:judge_identifier])

        puts "Successfully created submission with ID=#{submission.to_param}!"
      end
    end
  
    def extract_username(user_url)
      bot = Mechanize.new
      page = bot.get(DOMAIN + user_url + "&Itemid=20")

      container = page.search("html body table tr td.main table tr td.maincontent div.contentheading").first
      full_name = container.content.strip # Something like '        Andrés Mejía  (andmej)    '
      full_name =~ /\((.+)\)/
      $1
    end
  end
end