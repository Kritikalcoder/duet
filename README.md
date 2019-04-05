Duet is an expressive higher-order language, linear type system
and tool for automatically verifying differential privacy of arbitrary
higher-order programs. In addition to general purpose programming, it
supports encoding machine learning algorithms such as stochastic gradient
descent, as well as common auxiliary data analysis tasks such as
clipping, normalization and hyperparameter tuning.

## Installation

Install Stack: https://docs.haskellstack.org/en/stable/install_and_upgrade/

Install hpack: https://github.com/sol/hpack/blob/master/get-hpack.sh

## Running

To typecheck all the case studies just run ```make```.

To typecheck a specific example:

```shell
stack run -- check /path/to/examples/${example-name}
```

For example  

```shell
stack run -- check examples/complete/gd-pb.ed.duet
```

## Notes

* code, examples, and output use lots of math unicode symbols
