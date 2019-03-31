defmodule TeslaMate.LogTest do
  use TeslaMate.DataCase

  alias TeslaMate.Log

  describe "positions" do
    alias TeslaMate.Log.Position

    @valid_attrs %{name: "some name"}
    @update_attrs %{name: "some updated name"}
    @invalid_attrs %{name: nil}

    def position_fixture(attrs \\ %{}) do
      {:ok, position} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Log.create_position()

      position
    end

    test "list_positions/0 returns all positions" do
      position = position_fixture()
      assert Log.list_positions() == [position]
    end

    test "get_position!/1 returns the position with given id" do
      position = position_fixture()
      assert Log.get_position!(position.id) == position
    end

    test "create_position/1 with valid data creates a position" do
      assert {:ok, %Position{} = position} = Log.create_position(@valid_attrs)
      assert position.name == "some name"
    end

    test "create_position/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Log.create_position(@invalid_attrs)
    end

    test "update_position/2 with valid data updates the position" do
      position = position_fixture()
      assert {:ok, %Position{} = position} = Log.update_position(position, @update_attrs)
      assert position.name == "some updated name"
    end

    test "update_position/2 with invalid data returns error changeset" do
      position = position_fixture()
      assert {:error, %Ecto.Changeset{}} = Log.update_position(position, @invalid_attrs)
      assert position == Log.get_position!(position.id)
    end

    test "delete_position/1 deletes the position" do
      position = position_fixture()
      assert {:ok, %Position{}} = Log.delete_position(position)
      assert_raise Ecto.NoResultsError, fn -> Log.get_position!(position.id) end
    end

    test "change_position/1 returns a position changeset" do
      position = position_fixture()
      assert %Ecto.Changeset{} = Log.change_position(position)
    end
  end

  describe "states" do
    alias TeslaMate.Log.State

    @valid_attrs %{end_date: "2010-04-17T14:00:00Z", end_position_id: 42, start_data: "2010-04-17T14:00:00Z", start_position_id: 42, state: "some state"}
    @update_attrs %{end_date: "2011-05-18T15:01:01Z", end_position_id: 43, start_data: "2011-05-18T15:01:01Z", start_position_id: 43, state: "some updated state"}
    @invalid_attrs %{end_date: nil, end_position_id: nil, start_data: nil, start_position_id: nil, state: nil}

    def state_fixture(attrs \\ %{}) do
      {:ok, state} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Log.create_state()

      state
    end

    test "list_states/0 returns all states" do
      state = state_fixture()
      assert Log.list_states() == [state]
    end

    test "get_state!/1 returns the state with given id" do
      state = state_fixture()
      assert Log.get_state!(state.id) == state
    end

    test "create_state/1 with valid data creates a state" do
      assert {:ok, %State{} = state} = Log.create_state(@valid_attrs)
      assert state.end_date == DateTime.from_naive!(~N[2010-04-17T14:00:00Z], "Etc/UTC")
      assert state.end_position_id == 42
      assert state.start_data == DateTime.from_naive!(~N[2010-04-17T14:00:00Z], "Etc/UTC")
      assert state.start_position_id == 42
      assert state.state == "some state"
    end

    test "create_state/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Log.create_state(@invalid_attrs)
    end

    test "update_state/2 with valid data updates the state" do
      state = state_fixture()
      assert {:ok, %State{} = state} = Log.update_state(state, @update_attrs)
      assert state.end_date == DateTime.from_naive!(~N[2011-05-18T15:01:01Z], "Etc/UTC")
      assert state.end_position_id == 43
      assert state.start_data == DateTime.from_naive!(~N[2011-05-18T15:01:01Z], "Etc/UTC")
      assert state.start_position_id == 43
      assert state.state == "some updated state"
    end

    test "update_state/2 with invalid data returns error changeset" do
      state = state_fixture()
      assert {:error, %Ecto.Changeset{}} = Log.update_state(state, @invalid_attrs)
      assert state == Log.get_state!(state.id)
    end

    test "delete_state/1 deletes the state" do
      state = state_fixture()
      assert {:ok, %State{}} = Log.delete_state(state)
      assert_raise Ecto.NoResultsError, fn -> Log.get_state!(state.id) end
    end

    test "change_state/1 returns a state changeset" do
      state = state_fixture()
      assert %Ecto.Changeset{} = Log.change_state(state)
    end
  end

  describe "drive_states" do
    alias TeslaMate.Log.DriveState

    @valid_attrs %{end_date: "2010-04-17T14:00:00Z", end_position_id: 42, start_date: "2010-04-17T14:00:00Z", start_position_id: 42}
    @update_attrs %{end_date: "2011-05-18T15:01:01Z", end_position_id: 43, start_date: "2011-05-18T15:01:01Z", start_position_id: 43}
    @invalid_attrs %{end_date: nil, end_position_id: nil, start_date: nil, start_position_id: nil}

    def drive_state_fixture(attrs \\ %{}) do
      {:ok, drive_state} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Log.create_drive_state()

      drive_state
    end

    test "list_drive_states/0 returns all drive_states" do
      drive_state = drive_state_fixture()
      assert Log.list_drive_states() == [drive_state]
    end

    test "get_drive_state!/1 returns the drive_state with given id" do
      drive_state = drive_state_fixture()
      assert Log.get_drive_state!(drive_state.id) == drive_state
    end

    test "create_drive_state/1 with valid data creates a drive_state" do
      assert {:ok, %DriveState{} = drive_state} = Log.create_drive_state(@valid_attrs)
      assert drive_state.end_date == DateTime.from_naive!(~N[2010-04-17T14:00:00Z], "Etc/UTC")
      assert drive_state.end_position_id == 42
      assert drive_state.start_date == DateTime.from_naive!(~N[2010-04-17T14:00:00Z], "Etc/UTC")
      assert drive_state.start_position_id == 42
    end

    test "create_drive_state/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Log.create_drive_state(@invalid_attrs)
    end

    test "update_drive_state/2 with valid data updates the drive_state" do
      drive_state = drive_state_fixture()
      assert {:ok, %DriveState{} = drive_state} = Log.update_drive_state(drive_state, @update_attrs)
      assert drive_state.end_date == DateTime.from_naive!(~N[2011-05-18T15:01:01Z], "Etc/UTC")
      assert drive_state.end_position_id == 43
      assert drive_state.start_date == DateTime.from_naive!(~N[2011-05-18T15:01:01Z], "Etc/UTC")
      assert drive_state.start_position_id == 43
    end

    test "update_drive_state/2 with invalid data returns error changeset" do
      drive_state = drive_state_fixture()
      assert {:error, %Ecto.Changeset{}} = Log.update_drive_state(drive_state, @invalid_attrs)
      assert drive_state == Log.get_drive_state!(drive_state.id)
    end

    test "delete_drive_state/1 deletes the drive_state" do
      drive_state = drive_state_fixture()
      assert {:ok, %DriveState{}} = Log.delete_drive_state(drive_state)
      assert_raise Ecto.NoResultsError, fn -> Log.get_drive_state!(drive_state.id) end
    end

    test "change_drive_state/1 returns a drive_state changeset" do
      drive_state = drive_state_fixture()
      assert %Ecto.Changeset{} = Log.change_drive_state(drive_state)
    end
  end
end
