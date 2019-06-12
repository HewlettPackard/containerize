<!--- Copyright 2019 Hewlett Packard Enterprise Development LP --->

# Release criteria
This is a set of criteria to determine if this project is ready to release.

## Process
1. Test that publishing works
   1. Using dev-env with -l using the build containerize image
   1. Using .dev/registry.json
1. Test that `-q|--quiet works`
   1. Dockerfile
   1. Dockerfile.xyz
   1. xyz/Dockerfile
1. Test that `-l|--list works`
   1. With a repo having a single Dockerfile
   1. With a repo having multiple Dockerfiles
1. Test that `-t|--tag-as-subdir` works
   1. Dockerfile (tag should have no change, same with or without -t)
   1. Dockerfile.xyz (tag should be org/repo-xyz:version
   1. xyz/Dockerfile (tag should be org/repo-xyz:version, same with or without -t)
1. Test that `-q|--quiet` works with `-t|--tag-as-subdir`
   1. Dockerfile (should have no change, same with or without -t)
   1. Dockerfile.xyz (should be org/repo-xyz:version
   1. xyz/Dockerfile (should be org/repo-xyz:version, same with or without -t)
