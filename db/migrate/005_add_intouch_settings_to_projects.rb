class AddIntouchSettingsToProjects < ActiveRecord::Migration
  def up
    add_column :projects, :intouch_settings, :text
    Project.reset_column_information
    IntouchSetting.joins(:project).group_by(&:project_id).each do |project_id, settings|
      project = Project.find project_id
      settings_hash = {}
      settings.each do |setting|
        settings_hash[setting.name] = setting.value
      end
      project.settings_template_id = settings_hash['settings_template_id'] if settings_hash['settings_template_id'].present?

      telegram_settings_hash = settings_hash.select { |k, v| k.start_with? 'telegram' }

      project.telegram_settings = {}
      project.telegram_settings['groups'] = {}

      telegram_settings_hash.each do |k, v|
        status_and_recipient = k.match(/telegram_([a-z]+)_(\w+)/)
        status = status_and_recipient[1]
        recipient = status_and_recipient[2]

        if recipient == 'telegram_groups' and %w(alarm new working feedback).include? status
          if status == 'alarm'
            status_ids = IssueStatus.where(is_closed: false).pluck(:id).map(&:to_s)
            priority_ids = IssuePriority.alarm_ids.map(&:to_s)
          elsif %w(new working feedback).include? status
            status_ids = IssueStatus.send("#{status}_ids").map(&:to_s)
            priority_ids = IssuePriority.all.map(&:to_s)
          end
          v.keys.each do |group_id|
            project.telegram_settings['groups'][group_id] = {} unless project.telegram_settings['groups'][group_id]
            status_ids.each do |status_id|
              project.telegram_settings['groups'][group_id][status_id] = priority_ids
            end
          end
        else
          project.telegram_settings[status] = {} unless project.telegram_settings[status]
          project.telegram_settings[status][recipient] = v if v.present?
        end
      end

      email_settings_hash = settings_hash.select { |k, v| k.start_with? 'email' }
      project.email_settings = {}
      project.email_settings['cc'] = email_settings_hash['email_cc'] if email_settings_hash['email_cc'].present?
      email_settings_hash.each do |k, v|
        status_and_recipient = k.match(/email_([a-z]+)_(\w+)/)
        next unless status_and_recipient.present?
        status = status_and_recipient[1]
        recipient = status_and_recipient[2]
        next if recipient == 'telegram_groups'
        project.email_settings[status] = {} unless project.email_settings[status]
        project.email_settings[status][recipient] = v if v.present?
      end

      project.save
    end
  end

  def down
    remove_column :projects, :intouch_settings
  end
end
