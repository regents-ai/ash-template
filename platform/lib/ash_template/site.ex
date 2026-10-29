defmodule AshTemplate.Site do
  @moduledoc """
  What anyone may read about the site itself: whether it answers, its About page
  and developer documentation, the browser tools each Regent site offers and how
  an agent connects to siwa-server. Each read is also a hosted agent tool
  (`tools`).
  """

  use Ash.Domain, otp_app: :ash_template, extensions: [AshAi]

  resources do
    resource AshTemplate.Site.Info do
      define :health, action: :health
      define :about, action: :about
      define :docs, action: :docs
      define :sites_tools, action: :sites_tools, args: [:site]
      define :siwa_help, action: :siwa_help
    end
  end

  # The hosted agent tools: each runs the same action as its HTTP route, its
  # browser tool and its regents-cli command, and is named after them
  # (`AshTemplateWeb.Capabilities` checks both).
  tools do
    tool :health, AshTemplate.Site.Info, :health do
      description AshTemplate.Descriptions.hosted(:health)
    end

    tool :about, AshTemplate.Site.Info, :about do
      description AshTemplate.Descriptions.hosted(:about)
    end

    tool :docs, AshTemplate.Site.Info, :docs do
      description AshTemplate.Descriptions.hosted(:docs)
    end

    tool :sites_tools, AshTemplate.Site.Info, :sites_tools do
      description AshTemplate.Descriptions.hosted(:sites_tools)
    end

    tool :siwa_help, AshTemplate.Site.Info, :siwa_help do
      description AshTemplate.Descriptions.hosted(:siwa_help)
    end
  end
end
