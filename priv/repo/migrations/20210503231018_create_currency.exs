defmodule TeslaMate.Repo.Migrations.CreateCurrency do
  use Ecto.Migration

  alias TeslaMate.Repo
  
  def up do
    create table(:currencies, primary_key: false) do
      add :currency_code, :string, size: 3, null: false, primary_key: true
      add :currency_name, :string, null: false
		end
  
  	flush() 
  	
  	Ecto.Adapters.SQL.query!(
      Repo, "INSERT INTO CURRENCIES (currency_code, currency_name)
      VALUES ($1,$2)",
      [
      "AED","UAE Dirham"
      ] 
    )
  end
  
  def down do
    drop(table(:currencies))
  end    
end
