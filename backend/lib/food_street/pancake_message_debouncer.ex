defmodule FoodStreet.PancakeMessageDebouncer do
  @moduledoc """
  Gom các tin nhắn liên tiếp của nhà bán theo conversation trước khi xử lý.

  Mỗi tin mới reset timer của conversation đó. Khi hết khoảng im lặng, toàn bộ
  batch được chuyển cho handler theo đúng thứ tự nhận.
  """

  use GenServer

  @default_debounce_ms 10_000

  def start_link(opts) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  def enqueue(server \\ __MODULE__, message) do
    GenServer.call(server, {:enqueue, message})
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       batches: %{},
       debounce_ms: Keyword.get(opts, :debounce_ms, configured_debounce_ms()),
       task_supervisor: Keyword.get(opts, :task_supervisor, FoodStreet.TaskSupervisor),
       handler: Keyword.get(opts, :handler, {FoodStreet.PancakeInbound, :handle_messages, []})
     }}
  end

  @impl true
  def handle_call({:enqueue, message}, _from, state) do
    conversation_id = Map.fetch!(message, :conversation_id)
    message_id = Map.fetch!(message, :message_id)
    current = Map.get(state.batches, conversation_id, empty_batch())

    if MapSet.member?(current.message_ids, message_id) do
      {:reply, :duplicate, state}
    else
      if current.timer_ref, do: Process.cancel_timer(current.timer_ref)

      batch_ref = make_ref()

      timer_ref =
        Process.send_after(
          self(),
          {:flush, conversation_id, batch_ref},
          state.debounce_ms
        )

      batch = %{
        messages: [message | current.messages],
        message_ids: MapSet.put(current.message_ids, message_id),
        timer_ref: timer_ref,
        batch_ref: batch_ref
      }

      {:reply, :ok, put_in(state, [:batches, conversation_id], batch)}
    end
  end

  @impl true
  def handle_info({:flush, conversation_id, batch_ref}, state) do
    case state.batches[conversation_id] do
      %{batch_ref: ^batch_ref} = batch ->
        messages = Enum.reverse(batch.messages)

        Task.Supervisor.start_child(state.task_supervisor, fn ->
          run_handler(state.handler, messages)
        end)

        {:noreply, update_in(state.batches, &Map.delete(&1, conversation_id))}

      _ ->
        # Timer cũ có thể đã vào mailbox ngay trước khi bị cancel; batch_ref ngăn
        # nó flush nhầm batch vừa được gia hạn bởi tin mới.
        {:noreply, state}
    end
  end

  defp empty_batch do
    %{messages: [], message_ids: MapSet.new(), timer_ref: nil, batch_ref: nil}
  end

  defp run_handler({module, function, extra_args}, messages) do
    apply(module, function, [messages | extra_args])
  end

  defp configured_debounce_ms do
    :food_street
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:debounce_ms, @default_debounce_ms)
  end
end
