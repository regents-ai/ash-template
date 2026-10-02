defmodule AshTemplateWeb.Showcase.Utilities do
  @moduledoc false

  def privy(scenario) when scenario in [:valid, :expired, :audience] do
    now = 1_750_000_000
    key = JOSE.JWK.generate_key({:ec, "P-256"})
    {_, public_pem} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem()

    claims = %{
      "iss" => "privy.io",
      "aud" => if(scenario == :audience, do: "another-app", else: "showcase-practice"),
      "sub" => "did:privy:showcase-practice",
      "iat" => now - 10,
      "exp" => if(scenario == :expired, do: now - 1, else: now + 3600)
    }

    {_, token} = key |> JOSE.JWT.sign(%{"alg" => "ES256"}, claims) |> JOSE.JWS.compact()

    case RegentPrivy.verify_token(token,
           app_id: "showcase-practice",
           verification_key: public_pem,
           now: now
         ) do
      {:ok, _verified} ->
        "Practice sign-in check: valid. Nobody was signed in."

      {:error, reason} ->
        "Practice sign-in check: turned down, because #{rejection(reason)}. Nobody was signed in."
    end
  end

  defp rejection(:token_expired), do: "it has expired"
  defp rejection(:invalid_audience), do: "it was made for a different app"
  defp rejection(_reason), do: "it did not pass the check"

  def database do
    config = AshTemplate.Repo.config()

    if is_nil(config[:url]) and config[:hostname] in ["127.0.0.1", "localhost"] and
         config[:database] == "ash_template_dev" do
      case Ecto.Adapters.SQL.query(AshTemplate.Repo, "SELECT current_database(), 1", [],
             timeout: 2_000
           ) do
        {:ok, %{rows: [[name, 1]]}} -> "Reached the #{name} database. Nothing was written."
        {:error, _} -> "Local database unavailable."
      end
    else
      "This check needs the local development database."
    end
  catch
    :exit, _ -> "Local database process unavailable."
  end
end
