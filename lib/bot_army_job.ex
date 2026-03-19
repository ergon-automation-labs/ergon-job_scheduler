defmodule BotArmyJobScheduler do
  @moduledoc """
  BotArmyJobScheduler is the job scheduling and management bot implementation.

  Handles job scheduling, execution management, and status tracking
  within the Bot Army ecosystem.

  ## Schemas

  Message schemas are defined in `bot_army_schemas_job` and deployed to:
  `/etc/bot_army/schemas/job/`

  The bot consumes messages from NATS subjects like:
  - `job.schedule.create` - Schedule a job
  - `job.execution.start` - Start job execution
  - `job.status.update` - Update job status
  """

  @version "0.1.0"

  def version do
    @version
  end
end
