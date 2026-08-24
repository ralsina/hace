# Project markdownlint style, loaded via .mdlrc.
# https://github.com/markdownlint/markdownlint/blob/main/docs/configuration.md

all

# MD013 (line length): the README legitimately contains long lines in
# prose, URLs, and code/output blocks.
exclude_rule "MD013"

# MD029 (ordered list prefix): mdl 0.17 only accepts the all-"1." style,
# but the docs legitimately mix it with ascending "1. 2. 3." lists (both
# are CommonMark). Rewriting every list to one style would churn content
# for zero rendering difference.
exclude_rule "MD029"
