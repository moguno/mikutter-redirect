#! coding: UTF-8

Plugin.create(:mikutter_redirect) {
  UserConfig[:redirect_timer] ||= 10
  @messages = []
  @last_redirect_slug = nil

  module Looper
    def self.start(timer_set, &proc)
      proc.call

      Reserver.new(timer_set.call) {
        start(timer_set, &proc)
      }
    end
  end

  def fetch_message!
    message = @messages.find { |_| _ != @last_redirect_slug } ||
              (@messages.length != 0)?@messages[0]:nil

    if message
      @messages.delete(message)
    end

    message
  end

  Looper.start(-> { UserConfig[:redirect_timer] }) {
    message = fetch_message!

    if message
      Delayer.new {
        message[:modified] = Time.now
        timeline(:home_timeline) << message
      }
    end
  }

  # タイムラインのスラッフからUserConfigのキーを得る
  def make_config_key(i_timeline)
    "redirect_#{i_timeline.slug}".to_sym
  end

  # UserConfigから値を取得
  def get_config(i_timeline, key)
    config = UserConfig[make_config_key(i_timeline)]

    if config
      config.dup[key]
    else
      nil
    end
  end 

  # UserConfigに値を書き込み
  def set_config(i_timeline, kv)
    config = (UserConfig[make_config_key(i_timeline)] || {}).dup

    config = config.merge(kv)

    UserConfig[make_config_key(i_timeline)] = config
  end

  # i_tabからi_timelineを得る
  def get_i_timeline(i_tab)
    type_strict i_tab => Plugin::GUI::Tab

    i_tab.children.find { |a| a.is_a?(Plugin::GUI::Timeline) }
  end

  
  EXCEPT_TABS = [
    /^profile/,
    /^home_timeline$/,
    /^mentions$/,
  ]

  # リダイレクトON/OFF
  command(:redirect_to_home,
          name: _('redirect'),
          condition: lambda { |opt| 
            (opt.event != :contextmenu) &&
            (!EXCEPT_TABS.any?{ |_| opt.widget.slug.to_s =~ _ })
          },
          visible: true,
          icon: File.join(File.dirname(__FILE__), "redirect.png"),
          type: :toggle_button,
          value: lambda { |opt| 
            i_timeline = get_i_timeline(opt.widget)

            if i_timeline
              get_config(i_timeline, :on)
            else
              false
            end
          },
          role: :tab) { |opt|
      
    i_timeline = get_i_timeline(opt.widget)

    if i_timeline
      set_config(i_timeline, { :on => opt[:value] })

      if !opt[:value]
        set_config(i_timeline, { :last_redirected => nil })
      end
    end
  }


  # TLにメッセージが投入された
  on_gui_timeline_add_messages { |i_timeline, messages|
    Array(messages).each { |message|
      # 処理要件
      if [
        -> { get_config(i_timeline, :on) },
        -> { !message[:redirected] },
        -> {
          last_redirected = get_config(i_timeline, :last_redirected)

          if last_redirected
            last_redirected <= (message[:modified] || message[:created])
          else
            true
          end
        }
      ].all? { |a| a.call }
        set_config(i_timeline, { :last_redirected => (message[:modified] || message[:created]) })

        message[:redirected] = true
        message[:born_in] = i_timeline.slug

puts "add"
        @messages << message
      end
    }
  }
}
