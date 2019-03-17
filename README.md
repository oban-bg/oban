# Oban

Logo here
Brief description here

[![CircleCI](https://circleci.com/gh/sorentwo/oban.svg?style=svg)](https://circleci.com/gh/sorentwo/oban)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

- language
- hex version
- dependencies

# Table of Contents

- Introduction
- Features
  - Isolated queues
  - Scheduled jobs
  - Telemetry integration
  - Reliable execution/orphan rescue
  - Consumer draining, slow jobs are allowed to finish before shutdown
  - Historic Metrics
  - Node Metrics
  - Property Tested
- Why? | Philosophy | Rationale
- Installation
- Usage
  - Configuring Queues
  - Creating Workers
  - Enqueuing Jobs
  - Scheduling Jobs
- FAQ
- Contributing
- [License](#License)

## Usage

Oban isn't an application, it is started by a supervisor that must be included in your
application's supervision tree.  All of the configuration may be passed into the `Oban`
supervisor, allowing you to configure Oban like the rest of your application.

    # confg/config.exs
    config :my_app, Oban, repo: MyApp.Repo, queues: [default: 10, events: 50, media: 20]

    # lib/my_app/application.ex
    defmodule MyApp.Application do
      @moduledoc false

      use Application

      alias MyApp.{Endpoint, Repo}

      def start(_type, _args) do
        children = [
          Repo,
          Endpoint,
          {Oban, Application.get_env(:my_app, Oban)}
        ]

        Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
      end
    end

## License

Oban is released under the MIT license. See the [LICENSE](LICENSE.txt).
