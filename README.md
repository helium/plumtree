plumtree
=====

Plumtree is an implementation of Plumtree[1], the epidemic broadcast protocol.
It is extracted from the implementation in riak_core[2] and also, instead of
the riak_core ring and riak's ring gossip protocol, it includes a standalone
membership gossip, build around riak_dt[3]'s ORSWOT[4].

More information on the plumtree protocol and it's history we encourage you
to watch Jordan West's RICON West 2013 talk[5] and Joao Leitao & Jordan West's
RICON 2014 talk[6].

A special thanks to Jordan, Joao and the team at Basho for providing much of
the code contained in this library. 

1. http://www.gsd.inesc-id.pt/~jleitao/pdf/srds07-leitao.pdf
2. https://github.com/basho/riak_core
3. https://github.com/basho/riak_dt
4. http://haslab.uminho.pt/cbm/files/1210.3368v1.pdf
5. https://www.youtube.com/watch?v=s4cCUTPU8GI
6. https://www.youtube.com/watch?v=bo367a6ZAwM


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

Contributions from the community are encouraged. This project follows the 
git-flow workflow. If you want to contribute:

* Fork this repository 
* Make your changes and run the full test suite
 * Please include any additional tests for any additional code added
* Commit your changes and push them to your fork
* Open a pull request

We will review your changes, make appropriate suggestions and/or provide
feedback, and merge your changes when ready. 
