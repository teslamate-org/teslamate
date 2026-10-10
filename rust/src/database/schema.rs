// @generated automatically by Diesel CLI.

pub mod sql_types {
    #[derive(diesel::sql_types::SqlType)]
    #[diesel(postgres_type(name = "billing_type"))]
    pub struct BillingType;

    #[derive(diesel::sql_types::SqlType)]
    #[diesel(postgres_type(name = "states_status"))]
    pub struct StatesStatus;

    #[derive(diesel::sql_types::SqlType)]
    #[diesel(postgres_type(name = "unit_of_length"))]
    pub struct UnitOfLength;

    #[derive(diesel::sql_types::SqlType)]
    #[diesel(postgres_type(name = "unit_of_pressure"))]
    pub struct UnitOfPressure;

    #[derive(diesel::sql_types::SqlType)]
    #[diesel(postgres_type(name = "unit_of_temperature"))]
    pub struct UnitOfTemperature;
}

diesel::table! {
    addresses (id) {
        id -> Int4,
        #[max_length = 512]
        display_name -> Nullable<Varchar>,
        latitude -> Nullable<Numeric>,
        longitude -> Nullable<Numeric>,
        #[max_length = 255]
        name -> Nullable<Varchar>,
        #[max_length = 255]
        house_number -> Nullable<Varchar>,
        #[max_length = 255]
        road -> Nullable<Varchar>,
        #[max_length = 255]
        neighbourhood -> Nullable<Varchar>,
        #[max_length = 255]
        city -> Nullable<Varchar>,
        #[max_length = 255]
        county -> Nullable<Varchar>,
        #[max_length = 255]
        postcode -> Nullable<Varchar>,
        #[max_length = 255]
        state -> Nullable<Varchar>,
        #[max_length = 255]
        state_district -> Nullable<Varchar>,
        #[max_length = 255]
        country -> Nullable<Varchar>,
        raw -> Nullable<Jsonb>,
        inserted_at -> Timestamp,
        updated_at -> Timestamp,
        osm_id -> Nullable<Int8>,
        osm_type -> Nullable<Text>,
    }
}

diesel::table! {
    car_settings (id) {
        id -> Int8,
        suspend_min -> Int4,
        suspend_after_idle_min -> Int4,
        req_not_unlocked -> Bool,
        free_supercharging -> Bool,
        use_streaming_api -> Bool,
        enabled -> Bool,
        lfp_battery -> Bool,
    }
}

diesel::table! {
    cars (id) {
        id -> Int2,
        eid -> Int8,
        vid -> Int8,
        #[max_length = 255]
        model -> Nullable<Varchar>,
        efficiency -> Nullable<Float8>,
        inserted_at -> Timestamp,
        updated_at -> Timestamp,
        vin -> Text,
        name -> Nullable<Text>,
        trim_badging -> Nullable<Text>,
        settings_id -> Int8,
        exterior_color -> Nullable<Text>,
        spoiler_type -> Nullable<Text>,
        wheel_type -> Nullable<Text>,
        display_priority -> Int2,
        #[max_length = 255]
        marketing_name -> Nullable<Varchar>,
    }
}

diesel::table! {
    charges (id) {
        id -> Int4,
        date -> Timestamp,
        battery_heater_on -> Nullable<Bool>,
        battery_level -> Nullable<Int2>,
        charge_energy_added -> Numeric,
        charger_actual_current -> Nullable<Int2>,
        charger_phases -> Nullable<Int2>,
        charger_pilot_current -> Nullable<Int2>,
        charger_power -> Int2,
        charger_voltage -> Nullable<Int2>,
        fast_charger_present -> Nullable<Bool>,
        #[max_length = 255]
        conn_charge_cable -> Nullable<Varchar>,
        #[max_length = 255]
        fast_charger_brand -> Nullable<Varchar>,
        #[max_length = 255]
        fast_charger_type -> Nullable<Varchar>,
        ideal_battery_range_km -> Numeric,
        not_enough_power_to_heat -> Nullable<Bool>,
        outside_temp -> Nullable<Numeric>,
        charging_process_id -> Int4,
        battery_heater -> Nullable<Bool>,
        battery_heater_no_power -> Nullable<Bool>,
        rated_battery_range_km -> Nullable<Numeric>,
        usable_battery_level -> Nullable<Int2>,
    }
}

diesel::table! {
    charging_processes (id) {
        id -> Int4,
        start_date -> Timestamp,
        end_date -> Nullable<Timestamp>,
        charge_energy_added -> Nullable<Numeric>,
        start_ideal_range_km -> Nullable<Numeric>,
        end_ideal_range_km -> Nullable<Numeric>,
        start_battery_level -> Nullable<Int2>,
        end_battery_level -> Nullable<Int2>,
        duration_min -> Nullable<Int2>,
        outside_temp_avg -> Nullable<Numeric>,
        car_id -> Int2,
        position_id -> Int4,
        address_id -> Nullable<Int4>,
        start_rated_range_km -> Nullable<Numeric>,
        end_rated_range_km -> Nullable<Numeric>,
        geofence_id -> Nullable<Int4>,
        charge_energy_used -> Nullable<Numeric>,
        cost -> Nullable<Numeric>,
    }
}

diesel::table! {
    drives (id) {
        id -> Int4,
        start_date -> Timestamp,
        end_date -> Nullable<Timestamp>,
        outside_temp_avg -> Nullable<Numeric>,
        speed_max -> Nullable<Int2>,
        power_max -> Nullable<Int2>,
        power_min -> Nullable<Int2>,
        start_ideal_range_km -> Nullable<Numeric>,
        end_ideal_range_km -> Nullable<Numeric>,
        start_km -> Nullable<Float8>,
        end_km -> Nullable<Float8>,
        distance -> Nullable<Float8>,
        duration_min -> Nullable<Int2>,
        car_id -> Int2,
        inside_temp_avg -> Nullable<Numeric>,
        start_address_id -> Nullable<Int4>,
        end_address_id -> Nullable<Int4>,
        start_rated_range_km -> Nullable<Numeric>,
        end_rated_range_km -> Nullable<Numeric>,
        start_position_id -> Nullable<Int4>,
        end_position_id -> Nullable<Int4>,
        start_geofence_id -> Nullable<Int4>,
        end_geofence_id -> Nullable<Int4>,
        ascent -> Nullable<Int2>,
        descent -> Nullable<Int2>,
    }
}

diesel::table! {
    use diesel::sql_types::*;
    use super::sql_types::BillingType;

    geofences (id) {
        id -> Int4,
        #[max_length = 255]
        name -> Varchar,
        latitude -> Numeric,
        longitude -> Numeric,
        radius -> Int2,
        inserted_at -> Timestamp,
        updated_at -> Timestamp,
        cost_per_unit -> Nullable<Numeric>,
        session_fee -> Nullable<Numeric>,
        billing_type -> BillingType,
    }
}

diesel::table! {
    import_file_checkpoints (id) {
        id -> Int8,
        run_id -> Int8,
        #[max_length = 255]
        file_name -> Varchar,
        #[max_length = 255]
        file_fingerprint -> Varchar,
        completed_at -> Timestamp,
        inserted_at -> Timestamp,
        updated_at -> Timestamp,
    }
}

diesel::table! {
    import_rejections (id) {
        id -> Int8,
        run_id -> Int8,
        #[max_length = 255]
        file_name -> Varchar,
        #[max_length = 255]
        file_fingerprint -> Varchar,
        row -> Int4,
        #[max_length = 255]
        reason -> Varchar,
        fields -> Array<Nullable<Varchar>>,
        inserted_at -> Timestamp,
        updated_at -> Timestamp,
    }
}

diesel::table! {
    import_runs (id) {
        id -> Int8,
        #[max_length = 255]
        source_key -> Varchar,
        #[max_length = 255]
        status -> Varchar,
        #[max_length = 255]
        timezone -> Varchar,
        date_limit -> Nullable<Timestamp>,
        date_limit_captured -> Bool,
        car_id -> Nullable<Int8>,
        inserted_at -> Timestamp,
        updated_at -> Timestamp,
    }
}

diesel::table! {
    positions (id) {
        id -> Int4,
        date -> Timestamp,
        latitude -> Numeric,
        longitude -> Numeric,
        speed -> Nullable<Int2>,
        power -> Nullable<Int2>,
        odometer -> Nullable<Float8>,
        ideal_battery_range_km -> Nullable<Numeric>,
        battery_level -> Nullable<Int2>,
        outside_temp -> Nullable<Numeric>,
        elevation -> Nullable<Int2>,
        fan_status -> Nullable<Int4>,
        driver_temp_setting -> Nullable<Numeric>,
        passenger_temp_setting -> Nullable<Numeric>,
        is_climate_on -> Nullable<Bool>,
        is_rear_defroster_on -> Nullable<Bool>,
        is_front_defroster_on -> Nullable<Bool>,
        car_id -> Int2,
        drive_id -> Nullable<Int4>,
        inside_temp -> Nullable<Numeric>,
        battery_heater -> Nullable<Bool>,
        battery_heater_on -> Nullable<Bool>,
        battery_heater_no_power -> Nullable<Bool>,
        est_battery_range_km -> Nullable<Numeric>,
        rated_battery_range_km -> Nullable<Numeric>,
        usable_battery_level -> Nullable<Int2>,
        tpms_pressure_fl -> Nullable<Numeric>,
        tpms_pressure_fr -> Nullable<Numeric>,
        tpms_pressure_rl -> Nullable<Numeric>,
        tpms_pressure_rr -> Nullable<Numeric>,
    }
}

diesel::table! {
    schema_migrations (version) {
        version -> Int8,
        inserted_at -> Nullable<Timestamp>,
    }
}

diesel::table! {
    use diesel::sql_types::*;
    use super::sql_types::UnitOfLength;
    use super::sql_types::UnitOfTemperature;
    use super::sql_types::UnitOfPressure;

    settings (id) {
        id -> Int8,
        inserted_at -> Timestamp,
        updated_at -> Timestamp,
        unit_of_length -> UnitOfLength,
        unit_of_temperature -> UnitOfTemperature,
        preferred_range -> Range<Int4>,
        #[max_length = 255]
        base_url -> Nullable<Varchar>,
        #[max_length = 255]
        grafana_url -> Nullable<Varchar>,
        language -> Text,
        unit_of_pressure -> UnitOfPressure,
        theme_mode -> Text,
    }
}

diesel::table! {
    use diesel::sql_types::*;
    use super::sql_types::StatesStatus;

    states (id) {
        id -> Int4,
        state -> StatesStatus,
        start_date -> Timestamp,
        end_date -> Nullable<Timestamp>,
        car_id -> Int2,
    }
}

diesel::table! {
    updates (id) {
        id -> Int4,
        start_date -> Timestamp,
        end_date -> Nullable<Timestamp>,
        #[max_length = 255]
        version -> Nullable<Varchar>,
        car_id -> Int2,
    }
}

diesel::joinable!(cars -> car_settings (settings_id));
diesel::joinable!(charges -> charging_processes (charging_process_id));
diesel::joinable!(charging_processes -> addresses (address_id));
diesel::joinable!(charging_processes -> cars (car_id));
diesel::joinable!(charging_processes -> geofences (geofence_id));
diesel::joinable!(charging_processes -> positions (position_id));
diesel::joinable!(drives -> cars (car_id));
diesel::joinable!(import_file_checkpoints -> import_runs (run_id));
diesel::joinable!(import_rejections -> import_runs (run_id));
diesel::joinable!(positions -> cars (car_id));
diesel::joinable!(states -> cars (car_id));
diesel::joinable!(updates -> cars (car_id));

diesel::allow_tables_to_appear_in_same_query!(
    addresses,
    car_settings,
    cars,
    charges,
    charging_processes,
    drives,
    geofences,
    import_file_checkpoints,
    import_rejections,
    import_runs,
    positions,
    schema_migrations,
    settings,
    states,
    updates,
);
