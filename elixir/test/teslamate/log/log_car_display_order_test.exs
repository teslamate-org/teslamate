defmodule TeslaMate.LogCarDisplayOrderTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.{Log, Repo}
  alias TeslaMate.Log.Car

  import Ecto.Query

  defp cars_with_priorities(priorities) do
    for priority <- priorities do
      id = System.unique_integer([:positive])
      {:ok, car} = Log.create_car(%{eid: id, vid: id, vin: "#{id}F", display_priority: priority})
      car
    end
  end

  defp priorities_by_id do
    Repo.all(from c in Car, select: {c.id, c.display_priority}, order_by: c.id)
  end

  test "renumbers all cars 1..N after the first move" do
    [a, b, c, d, e, f] = cars_with_priorities([1, 1, 2, 3, 4, 5])

    assert {:ok, [b.id, a.id, c.id, d.id, e.id, f.id]} == Log.move_car(a.id, :down)

    assert priorities_by_id() ==
             [{a.id, 2}, {b.id, 1}, {c.id, 3}, {d.id, 4}, {e.id, 5}, {f.id, 6}]
  end

  test "orders equal priorities by id and swaps with the previous neighbour" do
    [a, b, c, d] = cars_with_priorities([1, 1, 1, 1])

    assert {:ok, [a.id, c.id, b.id, d.id]} == Log.move_car(c.id, :up)
    assert Log.list_car_ids_by_display_order() == [a.id, c.id, b.id, d.id]
    assert priorities_by_id() == [{a.id, 1}, {b.id, 3}, {c.id, 2}, {d.id, 4}]
  end

  test "changes nothing when a car is already at either end" do
    [a, b, c] = cars_with_priorities([1, 1, 1])

    assert {:ok, [a.id, b.id, c.id]} == Log.move_car(a.id, :up)
    assert {:ok, [a.id, b.id, c.id]} == Log.move_car(c.id, :down)
    assert priorities_by_id() == [{a.id, 1}, {b.id, 1}, {c.id, 1}]
  end

  test "moves the middle car up then back down among three cars" do
    [a, b, c] = cars_with_priorities([1, 2, 3])

    assert {:ok, [b.id, a.id, c.id]} == Log.move_car(b.id, :up)
    assert priorities_by_id() == [{a.id, 2}, {b.id, 1}, {c.id, 3}]

    assert {:ok, [a.id, b.id, c.id]} == Log.move_car(b.id, :down)
    assert priorities_by_id() == [{a.id, 1}, {b.id, 2}, {c.id, 3}]
  end

  test "returns an error for an unknown car" do
    cars_with_priorities([1])

    assert {:error, :not_found} == Log.move_car(-1, :up)
  end
end
