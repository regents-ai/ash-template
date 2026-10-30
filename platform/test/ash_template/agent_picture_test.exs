defmodule AshTemplate.AgentPictureTest do
  # Invariant: only a whole PNG, JPEG or WebP is ever opened, and what is kept is
  # always a 256 × 256 WebP of up to 64 KB.
  use ExUnit.Case, async: true

  alias AshTemplate.AgentPicture
  alias Vix.Vips.{Image, Operation}

  defp picture(width, height, suffix) do
    {:ok, bytes} = width |> Operation.black!(height, bands: 3) |> Image.write_to_buffer(suffix)
    bytes
  end

  # A PNG that names its size but holds next to nothing, as a small file that
  # opens into a huge picture does.
  defp png_header(width, height) do
    chunk = fn type, data ->
      <<byte_size(data)::32, type::binary, data::binary, :erlang.crc32(type <> data)::32>>
    end

    <<0x89, "PNG\r\n", 0x1A, "\n">> <>
      chunk.("IHDR", <<width::32, height::32, 8, 2, 0, 0, 0>>) <>
      chunk.("IDAT", :zlib.compress(<<0>>)) <> chunk.("IEND", "")
  end

  test "a PNG, JPEG or WebP is kept as a 256 × 256 WebP" do
    for suffix <- [".png", ".jpg", ".webp"] do
      assert {:ok, <<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>> = webp} =
               AgentPicture.make(picture(640, 360, suffix))

      {:ok, kept} = Image.new_from_buffer(webp)
      assert {Image.width(kept), Image.height(kept)} == {256, 256}
      assert byte_size(webp) <= 65_536
    end
  end

  test "nothing but a PNG, JPEG or WebP reaches the decoder" do
    svg = ~s(<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360"/>)
    pdf = "%PDF-1.4\n1 0 obj << /Type /Catalog >> endobj\n%%EOF\n"
    gif = <<"GIF89a", 1::little-16, 1::little-16, 0, 0, 0, ";">>

    for bytes <- [svg, pdf, gif, "", "RIFF"] do
      assert AgentPicture.make(bytes) == {:error, :not_a_picture}
    end
  end

  test "a file cut off part-way is refused" do
    png = picture(640, 360, ".png")

    assert AgentPicture.make(binary_part(png, 0, div(byte_size(png), 2))) ==
             {:error, :not_a_picture}
  end

  test "over 5 MB or 100 million pixels is refused" do
    assert AgentPicture.make(png_header(1, 1) <> :binary.copy(<<0>>, 5_000_000)) ==
             {:error, :too_big}

    assert AgentPicture.make(png_header(20_000, 20_000)) == {:error, :too_big}
  end
end
