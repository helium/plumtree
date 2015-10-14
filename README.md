Plumtree
=======================================================

[![Build Status](https://travis-ci.org/lasp-lang/plumtree.svg?branch=master)](https://travis-ci.org/lasp-lang/plumtree)

Plumtree is an implementation of [Plumtree](http://www.gsd.inesc-id.pt/~jleitao/pdf/srds07-leitao.pdf), the epidemic broadcast protocol.  It is extracted from the implementation in [Riak Core](https://github.com/basho/riak_core). Instead of the riak_core ring and riak's ring gossip protocol, it includes a standalone membership gossip, built around the [Riak DT](https://github.com/basho/riak_dt) [ORSWOT](http://haslab.uminho.pt/cbm/files/1210.3368v1.pdf).

More information on the plumtree protocol and it's history we encourage you to watch Jordan West's [RICON West 2013 talk](https://www.youtube.com/watch?v=s4cCUTPU8GI) and Joao Leitao & Jordan West's [RICON 2014 talk](https://www.youtube.com/watch?v=bo367a6ZAwM).

A special thanks to Jordan, Joao and the team at Basho for providing much of the code contained in this library.

Build
-----

    $ make

Testing
-------

    $ make test
    $ make xref
    $ make dialyzer

Contributing
----

Contributions from the community are encouraged. This project follows the git-flow workflow. If you want to contribute:

* Fork this repository
* Make your changes and run the full test suite
 * Please include any additional tests for any additional code added
* Commit your changes and push them to your fork
* Open a pull request

We will review your changes, make appropriate suggestions and/or provide feedback, and merge your changes when ready.
