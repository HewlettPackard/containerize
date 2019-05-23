# Roadmap for containerize tooling

Currently the HPE GLHC organization is maintaining three tools to solve a common
problem, namely the building and publishing of containers from a git repo.

* containerize.sh (this repo)
* gather (renamed [windlass](https://github.com/HewlettPackard/windlass))
* [dbuild](https://github.com/monasca/dbuild)

Our goal is to combine the best characteristics of these three tools into a
single, common tool that can be collaboratively maintained and open-sourced.

## Key characteristics of `containerize`

- Given a repo with just `Dockerfile`, does the right thing
- Actively developed to support new GLHC use cases

## Key characteristics of `gather`/`windlass` 

- Python application designed for extensibility
- Supports legacy project behavior using `artifacts.yaml`
- Supports unit testing

## Key characteristics of `dbuild`

- Simple, easy to use verb-based CLI
- Sane defaults, can optionally have a `build.yml` for more control


## High-level plan

- Based on `gather`/`windlass`, develop common Python tool
- Maintain `containerize` name
- Default behavior should be based on what `containerize` is doing now
- More planning for API details is required
- For now, use this repository as the collaboration point
