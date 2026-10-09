# The model every headless session the kit starts runs on unless told otherwise.
# Sourced, never run: pr-review.sh and ship-startable.sh each spelled this once,
# and a bump that reached one of them left the other a generation behind.
# A pinned id rather than the `opus` alias, so the review footer and the runner
# log name the model that actually ran, and a bump is a commit someone made.
KIT_DEFAULT_MODEL="claude-opus-5-5"
