# `univ2-pool-migrator`

Copyright has been transferred to Dai Foundation.

### Summary

Script library to be used in spell context whenever NST and NGT are introduced.

This script needs to be executed in the same spell than NGT is enabled, as otherwise it can't ensure to have 0 liquidity in the new Univ2 Pool (will revert otherwise).

It requires to be included after the two scripts that initialize NGT and NST respectively, and it can be ordered before or after the one that will replace the Flapper.

## Sherlock Contest:

You can find general (and particular for this repository) scope, definitions, rules, disclaimers and known issues that apply to the Sherlock contest [here](https://github.com/makerdao/sherlock-contest/blob/master/README.md).
Content listed there should be regarded as if it was in this readme.

