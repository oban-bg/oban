defmodule Oban.Config do
  # "GROUP" is the wrong value here
  # What is the overlap between IDENT and OTP_APP? Would I have multiple identities?
  defstruct [:group, :ident, :maxlen, :otp_app, streams: []]
end
