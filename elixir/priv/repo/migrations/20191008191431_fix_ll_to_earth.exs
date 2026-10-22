defmodule TeslaMate.Repo.Migrations.FixLlToEarth do
  use Ecto.Migration

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION public.ll_to_earth(float8, float8)
    RETURNS public.earth
    LANGUAGE SQL
    IMMUTABLE STRICT
    PARALLEL SAFE
    AS 'SELECT public.cube(public.cube(public.cube(public.earth()*cos(radians($1))*cos(radians($2))),public.earth()*cos(radians($1))*sin(radians($2))),public.earth()*sin(radians($1)))::public.earth';
    """)
  end

  def down do
    :ok
  end
end
