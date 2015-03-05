module QuickNotify
  module Notification

    PLATFORMS = {:email => 1, :ios => 2, :android => 3}
    STATUS_CODES = {:sending => 1, :sent => 2, :error => 3}

    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods

      def add(user, action, opts)
        n = self.new
        n.action = self.actions[action.to_sym]
        n.user = user
        n.message = opts[:message]
        n.short_message = opts[:short_message]
        n.full_message = opts[:full_message]
        n.subject = opts[:subject]
        n.delivery_platforms = opts[:delivery_platforms]
        n.meta = opts[:metadata]
        n.delivery_settings = opts[:delivery_settings] || {}
        saved = n.save
        if saved
          self.release_old_for(user.id)
        end
        return n
      end

      def quick_notify_notification_keys_for(db)
        if db == :mongomapper
          key :ac,  Integer
          key :uid, ObjectId
          key :oph, Hash
          key :sls, Array
          key :dvs, Array

          attr_alias :action, :ac
          attr_alias :user_id, :uid
          attr_alias :meta, :oph
          attr_alias :status_log, :sls

          timestamps!

        elsif db == :mongoid
          field :ac, as: :action, type: Integer
          field :uid, as: :user_id
          field :rm, as: :message, type: String
          field :sm, as: :short_message, type: String
          field :fm, as: :full_message, type: String
          field :sb, as: :subject, type: String
          field :pfs, as: :delivery_platforms, type: Array, default: []
          field :oph, as: :meta, type: Hash
          field :sls, as: :status_log, type: Array, default: []
          field :dsh, as: :delivery_settings, type: Hash, default: {}

          mongoid_timestamps!

        end
        belongs_to :user, :foreign_key => :uid
      end

      def actions
        @actions ||= {}
      end

      def device_class_is(cls)
        @device_class = cls
      end

      def device_class
        @device_class || ::Device
      end

      def add_action(act, val)
        self.actions[act] = val
      end

      def release_old_for(user_id)
        self.delete_all(:uid => user_id, :created_at => {'$lte' => 30.days.ago})
      end

    end

    ## DELIVERY

    def deliver
      self.delivery_platforms.each do |plat|
        case plat.to_sym
        when :ios
          self.deliver_ios
        when :email
          self.deliver_email
        end
      end
    end

    def deliver_email
      begin
        QuickNotify::Mailer.notification_email(self).deliver
        self.log_status(:email, :sent, self.user.email)
      rescue => e
        self.log_status(:email, :error, self.user.email)
        puts e
        puts e.backtrace.join("\n\t")
      end
    end

    def deliver_ios
      self.class.device_class.registered_to(self.user.id).running_ios.each do |device|
        if device.is_dormant?
          device.unregister
        else
          self.log_status(:ios, :sending, device.id)
          ret = QuickNotify::Sender.send_ios_notification(device, self)
          self.log_status(:ios, (ret == true ? :sent : :error), device.id)
        end
      end
    end

    def deliver_android

    end

    def log_status(plat, code, note=nil)
      self.status_log << {plat: plat, code: STATUS_CODES[code], note: note.to_s}
      self.save
    end

    ## HELPERS

    def action_sym
      self.class.actions.rassoc(self.action).first
    end

    def html_message
      return nil if full_message.nil?
      return full_message.gsub(/\n/, "<br>")
    end

    def delivery_settings_for(type)
      return (self.delivery_settings[type.to_s] || {}).with_indifferent_access
    end

  end
end
