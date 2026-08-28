defmodule FoodStreet.PancakeMessageDebouncerTest do
  use ExUnit.Case, async: true

  alias FoodStreet.PancakeMessageDebouncer

  def deliver(messages, test_pid), do: send(test_pid, {:delivered, messages})

  def deliver_with_gate([%{conversation_id: "slow"}] = messages, test_pid) do
    send(test_pid, {:handler_started, self()})

    receive do
      :continue -> send(test_pid, {:delivered, messages})
    end
  end

  def deliver_with_gate(messages, test_pid), do: send(test_pid, {:delivered, messages})

  test "gom các tin cùng conversation thành một batch sau khoảng im lặng" do
    task_supervisor = start_supervised!(Task.Supervisor)

    debouncer =
      start_supervised!(
        {PancakeMessageDebouncer,
         name: nil,
         debounce_ms: 20,
         task_supervisor: task_supervisor,
         handler: {__MODULE__, :deliver, [self()]}}
      )

    first = %{conversation_id: "conv-1", message_id: "msg-1", text: "hết"}
    second = %{conversation_id: "conv-1", message_id: "msg-2", text: "xôi nhé"}

    assert :ok = PancakeMessageDebouncer.enqueue(debouncer, first)
    assert :ok = PancakeMessageDebouncer.enqueue(debouncer, second)

    assert_receive {:delivered, [^first, ^second]}, 100
    refute_receive {:delivered, _}, 30
  end

  test "tin mới reset thời gian chờ của conversation" do
    task_supervisor = start_supervised!(Task.Supervisor)

    debouncer =
      start_supervised!(
        {PancakeMessageDebouncer,
         name: nil,
         debounce_ms: 80,
         task_supervisor: task_supervisor,
         handler: {__MODULE__, :deliver, [self()]}}
      )

    first = %{conversation_id: "conv-1", message_id: "msg-1", text: "hết"}
    second = %{conversation_id: "conv-1", message_id: "msg-2", text: "xôi nhé"}

    assert :ok = PancakeMessageDebouncer.enqueue(debouncer, first)
    refute_receive {:delivered, _}, 50

    assert :ok = PancakeMessageDebouncer.enqueue(debouncer, second)
    refute_receive {:delivered, _}, 50
    assert_receive {:delivered, [^first, ^second]}, 60
  end

  test "handler chậm của một conversation không chặn conversation khác" do
    task_supervisor = start_supervised!(Task.Supervisor)

    debouncer =
      start_supervised!(
        {PancakeMessageDebouncer,
         name: nil,
         debounce_ms: 0,
         task_supervisor: task_supervisor,
         handler: {__MODULE__, :deliver_with_gate, [self()]}}
      )

    slow = %{conversation_id: "slow", message_id: "msg-1", text: "đợi"}
    fast = %{conversation_id: "fast", message_id: "msg-2", text: "xử lý ngay"}

    assert :ok = PancakeMessageDebouncer.enqueue(debouncer, slow)
    assert_receive {:handler_started, handler_pid}, 100

    enqueue_fast = Task.async(fn -> PancakeMessageDebouncer.enqueue(debouncer, fast) end)
    enqueue_result = Task.yield(enqueue_fast, 100)
    send(handler_pid, :continue)

    assert enqueue_result == {:ok, :ok}
    assert_receive {:delivered, [^fast]}, 100
  end
end
