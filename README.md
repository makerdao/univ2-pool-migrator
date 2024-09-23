# `univ2-pool-migrator`

Copyright has been transferred to Dai Foundation.

### Summary

Script library to be used in spell context whenever USDS and SKY are introduced.

This script needs to be executed in the same spell than SKY is enabled, as otherwise it can't ensure to have 0 liquidity in the new Univ2 Pool (will revert otherwise).

It requires to be included after the two scripts that initialize SKY and USDS respectively, and it can be ordered before or after the one that will replace the Flapper.
