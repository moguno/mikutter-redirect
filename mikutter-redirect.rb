#! coding: UTF-8

Plugin.create(:mikutter_redirect) {
  UserConfig[:redirect_timer] ||= 10
  @messages = []
  @last_redirect_slug = nil

  # 繰り返しReserverを呼ぶ
  module Looper
    def self.start(timer_set, &proc)
      proc.call

      Reserver.new(timer_set.call) {
        start(timer_set, &proc)
      }
    end
  end


  # メッセージを1つ取り出す
  def fetch_message!
    message = @messages.find { |_| _[:born_in] != @last_redirect_slug } ||
              (@messages.length != 0)?@messages[0]:nil

    if message
      @messages.delete(message)
    end

    message
  end


  # メッセージをホームタイムラインに混ぜ込む
  Looper.start(-> { UserConfig[:redirect_timer] }) {
    message = fetch_message!

    if message
      Delayer.new {
        timeline(:home_timeline) << message
        message[:modified] = Time.now
      }
    end
  }


  # タイムラインのスラッフからUserConfigのキーを得る
  def make_config_key(timeline_slug)
    "redirect_#{timeline_slug}".to_sym
  end


  # UserConfigから値を取得
  def get_config(timeline_slug, key)
    config = UserConfig[make_config_key(timeline_slug)]

    if config
      config.dup[key]
    else
      nil
    end
  end 


  # UserConfigに値を書き込み
  def set_config(timeline_slug, kv)
    config = (UserConfig[make_config_key(timeline_slug)] || {}).dup

    config = config.merge(kv)

    UserConfig[make_config_key(timeline_slug)] = config
  end


  # i_tabからi_timelineを得る
  def get_i_timeline(i_tab)
    type_strict i_tab => Plugin::GUI::Tab

    i_tab.children.find { |a| a.is_a?(Plugin::GUI::Timeline) }
  end

  
  # 除外するタブのslug
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
              get_config(i_timeline.slug, :on)
            else
              false
            end
          },
          role: :tab) { |opt|
      
    i_timeline = get_i_timeline(opt.widget)

    if i_timeline
      set_config(i_timeline.slug, { :on => opt[:value] })

      if !opt[:value]
        set_config(i_timeline.slug, { :last_redirected => nil })
      end
    end
  }


  # 色選択
  command(:redirect_color,
          name: _('redirect_color'),
          condition: lambda { |opt| 
            (opt.event != :contextmenu) &&
            (!EXCEPT_TABS.any?{ |_| opt.widget.slug.to_s =~ _ })
          },
          visible: true,
          icon: File.join(File.dirname(__FILE__), "redirect.png"),
          type: :color_button,
          value: lambda { |opt| 
            i_timeline = get_i_timeline(opt.widget)

            if i_timeline && get_config(i_timeline.slug, :color)
              get_config(i_timeline.slug, :color)
            else
              [0, 0, 0]
            end
          },
          role: :tab) { |opt|
      
    i_timeline = get_i_timeline(opt.widget)

    if i_timeline
      set_config(i_timeline.slug, { :color => opt[:value] })
    end
  }


  # TLにメッセージが投入された
  on_gui_timeline_add_messages { |i_timeline, messages|
    Array(messages).each { |message|
      # 処理要件
      if [
        -> { get_config(i_timeline.slug, :on) },
        -> { !message[:redirected] },
        -> {
          last_redirected = get_config(i_timeline.slug, :last_redirected)

          if last_redirected
            last_redirected <= (message[:modified] || message[:created])
          else
            true
          end
        }
      ].all? { |a| a.call }
        set_config(i_timeline.slug, { :last_redirected => (message[:modified] || message[:created]) })

        message[:redirected] = true
        message[:born_in] = i_timeline.slug

        @messages << message
      end
    }
  }


  # メッセージの文字色を設定する
  filter_message_font_color { |message, color|
    result_color = if message[:redirected] && get_config(message[:born_in], :color)
      get_config(message[:born_in], :color) 
    else
      color
    end

    [message, result_color]
  }
}
