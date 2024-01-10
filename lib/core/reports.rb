require 'warning'
require 'fileutils'
require 'report_builder'
Warning.ignore(/Passing/)

module Reports
  @@report = {
      "CASES" => {},
      "ERRORS" => {},
      "TOTAL_CASES" => [],
      "CASE_LOGS" => {}
  }
  @@cucumber_report = nil

  def report_error(message)
    _case = message.match(/case '(\S+)'/)[1] if  message.match(/case '(\S+)'/)
    screenshot_path = message.match(/Screenshot: (.*)/)[1] if message.match(/Screenshot: (.*)/)
    if _case && !_case.empty?
      @@report["ERRORS"][_case] = [] unless @@report["ERRORS"][_case]
      @@report["ERRORS"][_case].append(
      {"error_message" => message, "screenshot_path" => screenshot_path}) 
    end
  end

  def report_case(message)
    _case = message.match(/Case Execution for '(.*)'/)[1] if  message.match(/Case Execution for '(.*)'/)
    @@report["TOTAL_CASES"].append _case if _case
  end

  def report_step(message, main_case, id)
    @@report["CASES"][main_case+id] = {} unless @@report["CASES"][main_case+id]
    @@report["CASES"][main_case+id]["passed"] = [] unless @@report["CASES"][main_case+id]["passed"]
    @@report["CASES"][main_case+id]["passed"].append({"step" => message})
  end

  def report_step_fail(_case, main_case, id, error_message, is_precase = false)
    @@report["CASES"][main_case+id] = {} unless @@report["CASES"][main_case+id]
    @@report["CASES"][main_case+id]["failed"] = [] unless @@report["CASES"][main_case+id]["fail_steps"]
    screenshot_path = error_message.match(/Screenshot: (.*)/)[1] if error_message.match(/Screenshot: (.*)/)
    # if the precase fails, report will not show the step as failed avoiding main test failure.
    if is_precase
      @@report["CASES"][main_case+id]["passed"].append(
        {"step" => _case, "error_message" => error_message, "screenshot_path" => screenshot_path})
    else
        @@report["CASES"][main_case+id]["failed"].append(
          {"step" => _case, "error_message" => error_message, "screenshot_path" => screenshot_path})
    end
  end

  def set_case_log_report(_case, path)
    @@report["CASE_LOGS"][_case] = path
  end
  
  # process_report_cucumber() Parses the @@report var into cucumber json format
  def process_report_cucumber()
    cucumber_report = []
    @@report["CASES"].each do |main_case_id, main_case_info|
      main_case = main_case_id.match(/(.*)\ [0-9]*-[0-9]*-[0-9]* [0-2][0-9]:[0-5][0-9]:[0-5][0-9].\d*/)[1] #Extracting case name
      cucumber_report_s = {
      "description" => main_case, # Case File Description
      "keyword" => main_case, # Case File Keywords
      "name" => main_case,
      "id" => main_case_id, # Case File ID = Relative Path
      "tags" => [], # Case File Tags
      "uri" => main_case_id, # Case File
      "elements" => []
      }
      # GET STEPS
      case_info = nil
      steps_cucumber = []
      case_file = find_case_file(main_case)
      end_time = nil #Holds the end time of the action 
      starting_time = nil #Holds the starting time of the action
      case_line = 0
      # GETTING CASE LOGS FROM @@report TO INCLUDE THEM IN CUCUMBER REPORT
      main_case_info.each do |step_type, steps_report|
        # step_type CAN BE failed/succeed FOR NOW, BUT MIGHT INCREASE TO warn/others
        steps_report.each do |step|       
          #Checks if the step is an Action  
          if(step["step"].include? "Action: ")
            keyword, step_description = "Step ", step["step"] #Assigns Step as the keyword and the action as description for the report log
            # step_description_not_frozen = step_description.dup.force_encoding("ASCII-8BIT")
            # step_description_utf8_string = step_description_not_frozen.encode("UTF-8", "ASCII-8BIT", invalid: :replace, undef: :replace, replace: "")
            if end_time.nil?
              starting_time = main_case_id.match(/[0-9]*-[0-9]*-[0-9]* [0-2][0-9]:[0-5][0-9]:[0-5][0-9].\d*/)[0] #For the first action it takes the case starting time as the action starting time
            end
            end_time = step["step"].match(/[0-9]*-[0-9]*-[0-9]* [0-2][0-9]:[0-5][0-9]:[0-5][0-9].\d*/)[0] 
            duration = ((Time.parse(end_time) - Time.parse(starting_time))*1000000000) #Duration needs to be multiple by 10^9 because the report duration is based on nanoseconds.
            starting_time = end_time #The end time of an action is the starting time of the next action
          elsif step["error_message"]
            # ERROR STEPS DO NOT HAVE GHERKIN PREFIX
            step_description = step["step"] if step["step"]
            # lol problem may not be hereee
            # step_description_not_frozen = step_description.dup.force_encoding("ASCII-8BIT")
            # step_description_utf8_string = step_description_not_frozen.encode("UTF-8", "ASCII-8BIT", invalid: :replace, undef: :replace, replace: "")
            # step_description_utf8_string = "error lol1"
            # step_description.scrub
          #Checks if the step is a case step. 
          elsif step["step"].match(/\w+ /)
            step_description = step["step"]
            # step_description_not_frozen = step_description.dup.force_encoding("ASCII-8BIT")
            # step_description_utf8_string = step_description_not_frozen.encode("UTF-8", "ASCII-8BIT", invalid: :replace, undef: :replace, replace: "")
            # step_description_utf8_string = "case step lol2"
            # step_description.scrub
            keyword = step["step"].match(/\w+ /)[0].strip! #Keyword is the case name so that it shows in bold on the report
                                  #GETS MAIN CASE INFO: FILE AND LINE WHERE IT START, LINE WHERE THE STEP IS CALLED
            case_info = get_case_info(main_case, case_file, step_description)
            #GETS STEP CASE INFO: FILE AND LINE WHERE IT START
            step_info = get_case_info(keyword, find_case_file(keyword))
            unless case_info.nil? 
              step_line = case_info["step_line"].to_i 
              case_line = case_info["case_line"].to_i
            end
            unless step_info.nil? 
              location = "#{step_info["case_file"]}:#{step_info["case_line"]}"
            end
           #Removing keyword from the description so that the case name is not repeated
            begin
                # step_description_utf8_string.slice! keyword 
                step_description.slice! keyword 
            rescue => e
                # step_description_utf8_string.dup.slice! keyword #Rescues the frozen string exception. 
                step_description.dup.slice! keyword #Rescues the frozen string exception. 
            end
          end

          data = _convert_into_cucumber_emb(step)
          steps_cucumber.append(
            {
              "arguments" => [],
              # "keyword" => keyword ||= step_description_utf8_string,
              "keyword" => keyword ||= step_description,
              "embeddings" => data,
              "line" => step_line,
              # "name" => step_description_utf8_string,
              "name" => step_description,
              "match" => {
              "location" => location
              },
              "result" => {
              "status" => step_type,
              "error_message" => step["error_message"],
              "duration" => duration
              }
            }
          )
        end
      end
      # ADD STEPS INFO FROM @@report
      cucumber_report_s["elements"].append(
        {
          "id" => main_case,
          "keyword" => "Scenario",
          "line" => case_line,
          "name" => main_case,
          "tags" => [], # Case Tags,
          "type" => "scenario",
          "steps" => steps_cucumber
        }
      )
      # APPEND CUCUMBER SCENARIO TO THE LIST OF CASES RAN
      cucumber_report.append(cucumber_report_s)
    end
    @@cucumber_report = cucumber_report
  end

  # generate_report() Generates the JSON file under Reports/logs/*.json
  def generate_report(report_type, file_name)
    jsonfile_path = ""
    if report_type == "testray"
        jsonfile_path = File.join(Dir.pwd, "Reports", "logs", "#{file_name}.json")
        File.open(jsonfile_path, "w+") { |f| f.write(@@report.to_json) }
    elsif report_type == "cucumber"
        jsonfile_path = File.join(Dir.pwd, "Reports", "logs", "cucumber_#{file_name}.json")
        File.open(jsonfile_path, "w+") { |f| f.write(process_report_cucumber().to_json) }
    end
    #generates html report with report_builder gem. Report is saved on the Reports/logs directory
    options = {
      input_path: jsonfile_path,
      report_path: File.join(Dir.pwd, "Reports", "logs", "cucumber_#{file_name}"),
      report_types: ['html'],
      report_title: file_name,
    }  
    ReportBuilder.build_report options

    return jsonfile_path
  end
end

def _convert_into_cucumber_emb(data)
  embeddings = []
  return embeddings unless data || data["screenshot_path"]
  img_b64 = nil
  if data["screenshot_path"] && File.exist?(data["screenshot_path"])
    File.open(data["screenshot_path"], 'rb') do |img|
        img_b64 = Base64.strict_encode64(img.read)
    end
    embedding = {
        "media" => {
            "type" => "image/png"
        },
        "mime_type" => "image/png",
        "data" => img_b64
    }
    embeddings.append(embedding)
  end

  return embeddings
end
