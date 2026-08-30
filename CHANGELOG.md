# Changelog

## [0.2.0](https://github.com/MoXcz/knapp.nvim/compare/v0.1.0...v0.2.0) (2026-08-30)


### Features

* complete [[ links with blink, and mark links that point nowhere ([dff074b](https://github.com/MoXcz/knapp.nvim/commit/dff074bcb2a6fb8900e21266274bf30966873c12))
* **dashboard:** add a vault dashboard and a task-list reader ([8c090da](https://github.com/MoXcz/knapp.nvim/commit/8c090daca59a7349c91c76e79fbaf3beb344d2d0))
* journal/calendar feature flags, documented public API ([019c3c4](https://github.com/MoXcz/knapp.nvim/commit/019c3c45fad3308a08d27bd050eaf0376bb25e50))


### Bug Fixes

* close the edges the pre-0.2.0 ([2719bf3](https://github.com/MoXcz/knapp.nvim/commit/2719bf33282802689e26d46f4e0c125c156ca3d5))
* stop flagging extra ignore entries as unknown options ([c99a2d8](https://github.com/MoXcz/knapp.nvim/commit/c99a2d853c718ac07f4827591d7912cf4afdc77e))


### Performance

* build the cold index in background slices instead of freezing the UI ([f3ff7ae](https://github.com/MoXcz/knapp.nvim/commit/f3ff7ae83afdb9dbf25afd747b8b11d196a8a571))
* precompute lowered names, per-vault cache file, hashed date tokens ([a2f6287](https://github.com/MoXcz/knapp.nvim/commit/a2f62879f5fe3cdeb821dd3bb30109fd774137cc))
* remove stat loops and quadratic link scan from hot paths ([c698ab8](https://github.com/MoXcz/knapp.nvim/commit/c698ab8d70430c31fdf6b44e8aca42904973e0ed))

## 0.1.0 (2026-08-29)


### Features

* **health:** add :checkhealth knapp ([3e96fa5](https://github.com/MoXcz/knapp.nvim/commit/3e96fa5d38af7a0026ca08795a8e6e7bfff6994d))
* **keys:** expose every action as a &lt;Plug&gt; mapping ([5c7fee0](https://github.com/MoXcz/knapp.nvim/commit/5c7fee055f36614f64e48ef20afb0b59d6650639))


### Bug Fixes

* correct weekly note format, report failures usefully ([5d5b28f](https://github.com/MoXcz/knapp.nvim/commit/5d5b28fa921cc40573209de7b7378ec196d5a17d))
* **link:** scan whole files, not single lines ([b2e2281](https://github.com/MoXcz/knapp.nvim/commit/b2e22813df6b7c6ce8c7db23a1294105ade02b8a))
* make typecheck actually run, and pass ([ee0fcfc](https://github.com/MoXcz/knapp.nvim/commit/ee0fcfc4a751b9c36546c002cda54962bf4e8d40))
* repair NAV reference and health scope, make lint able to fail ([dc0e5ae](https://github.com/MoXcz/knapp.nvim/commit/dc0e5ae0b1bfac091dcd0297d7bfc802d1f00870))


### Performance

* cache backlink scans and debounce autocommand storms ([cc06de3](https://github.com/MoXcz/knapp.nvim/commit/cc06de3f503d54b5120eefc18ee96fd555c36fe2))
* **index:** update incrementally instead of rebuilding on every write ([f62f383](https://github.com/MoXcz/knapp.nvim/commit/f62f3838a048379d0dc619ab3901287ea5f4b1a4))


### Refactors

* validate config against a schema shared with health ([6d7efa6](https://github.com/MoXcz/knapp.nvim/commit/6d7efa62551bd5194ef1d54affe35dcdf2aca652))


### Documentation

* add generated vimdoc ([4d65c54](https://github.com/MoXcz/knapp.nvim/commit/4d65c54f0e329f9b7d1dc53340263616efaf3b68))
* generate vimdoc from README with panvimdoc ([c134423](https://github.com/MoXcz/knapp.nvim/commit/c134423f0fc7a7cd68c4f119eb36ee26d4b43d71))
