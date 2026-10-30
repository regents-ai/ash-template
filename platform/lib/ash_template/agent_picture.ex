defmodule AshTemplate.AgentPicture do
  @moduledoc """
  Turns a picture an owner uploads for their agent into the one kept for it: a
  256 × 256 WebP cut from the middle of the upload, carrying nothing else the
  file held (place, camera, colour notes). The shared agents library keeps it
  and takes a WebP of up to 64 KB only.
  """

  alias Vix.Vips.Image
  alias Vix.Vips.Operation

  @side 256
  @max_upload 5_000_000
  @max_kept 65_536
  # A small file can still open into a huge picture, and decoding costs memory
  # by the pixel; 40 million is above most phone cameras.
  @max_pixels 40_000_000

  @doc "The largest upload taken, in bytes."
  def max_upload, do: @max_upload

  @doc """
  The picture kept for the upload `bytes`: `{:ok, webp}`, or `{:error, reason}`
  where reason is `:not_a_picture` (not a whole PNG, JPEG or WebP), `:too_big`
  (over 5 MB or 40 million pixels) or `:too_detailed` (still over 64 KB once
  made).
  """
  def make(bytes) when byte_size(bytes) > @max_upload, do: {:error, :too_big}

  def make(bytes) do
    with {:ok, loader} <- loader(bytes),
         {:ok, picture} <- open(loader, bytes),
         :ok <- within_pixels(picture),
         {:ok, webp} <- square(picture) do
      kept(webp)
    end
  end

  # Chosen from the file's first bytes, so libvips never picks a decoder itself.
  defp loader(<<0x89, "PNG\r\n", 0x1A, "\n", _::binary>>), do: {:ok, &Operation.pngload_buffer/2}
  defp loader(<<0xFF, 0xD8, 0xFF, _::binary>>), do: {:ok, &Operation.jpegload_buffer/2}

  defp loader(<<"RIFF", _size::binary-size(4), "WEBP", _::binary>>),
    do: {:ok, &Operation.webpload_buffer/2}

  defp loader(_bytes), do: {:error, :not_a_picture}

  # Opening reads only the header, so the size is known before any decoding.
  # The picture is then decoded once, top to bottom, and a file cut off
  # part-way is turned away rather than kept half grey.
  defp open(loader, bytes) do
    case loader.(bytes, access: :VIPS_ACCESS_SEQUENTIAL, "fail-on": :VIPS_FAIL_ON_TRUNCATED) do
      {:ok, {picture, _flags}} -> {:ok, picture}
      {:error, _reason} -> {:error, :not_a_picture}
    end
  end

  defp within_pixels(picture) do
    if Image.width(picture) * Image.height(picture) <= @max_pixels,
      do: :ok,
      else: {:error, :too_big}
  end

  defp square(picture) do
    with {:ok, square} <-
           Operation.thumbnail_image(picture, @side,
             height: @side,
             crop: :VIPS_INTERESTING_CENTRE
           ),
         {:ok, webp} <- Image.write_to_buffer(square, ".webp[Q=75,keep=none]") do
      {:ok, webp}
    else
      {:error, _reason} -> {:error, :not_a_picture}
    end
  end

  defp kept(webp) when byte_size(webp) <= @max_kept, do: {:ok, webp}
  defp kept(_webp), do: {:error, :too_detailed}
end
