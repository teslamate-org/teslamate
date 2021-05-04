defmodule TeslaMate.Repo.Migrations.AddFieldsToGeofences do
  use Ecto.Migration

  def change do
    alter table(:geofences) do
      add :currency_code, references(:currencies, column: :currency_code, type: :string, size: 3 ), null: true
 			add :country_code,  references(:countries, column: :country_code, type: :string, size: 2 ), null: true     
      add :supercharger, :boolean, default: true
      add :provider, :string, null: true
      add :active, :boolean, default: true
    end
  end
  
  
	def down do  
		alter table(:geofences) do
  		remove_if_exists :currency_code, :string
  	  remove_if_exists :country_code, :string
  	  remove_if_exists :supercharger, :boolean
  	  remove_if_exists :provider, :string
  	  remove_if_exists :active, :boolean
  	end
	end  
end
