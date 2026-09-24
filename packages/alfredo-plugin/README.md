# Alfredo DSH plugin

Requires DSH `>=0.1.5-rc.3`.

Install from this package/repository with:

```sh
dsh plugin --profile web add /path/to/alfredo/packages/alfredo-plugin
dsh --profile web
```

The package exposes a `dsh.bundle` patch and a `dsh.client` browser entry. The
browser entry registers the `Alfredo` conversation view using the official DSH
slot. Host operations use authenticated DSH connection routes and invoke the
Alfredo CLI with argument arrays.
