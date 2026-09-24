# AADO External Git Backup - Restore Verification

Date: 2026-09-23
Result: PASS

## Remote

Repository:

https://github.com/GLR2026/AADO.git

Branch:

main

## Verified commit

Short commit:

7ac7295

Full commit:

7ac72956960b76a1ffab38ffdf1746ee53477998

## Verified Git tree

892b7f3f2c9b0f83e5067b9a8ffcfa16c5c861b6

## Restore procedure

A clean clone was created from the remote repository into:

C:\AADO_PRIVATE\tmp\restore-test

The restored repository was compared against the original repository.

## Checks

PASS - Original and restored repositories point to the same commit.

PASS - Git tree hashes are identical.

PASS - Tracked file lists are identical.

PASS - All versioned Git blob IDs are identical.

PASS - Both working trees are clean.

Tracked files verified: 7.

## Important lesson

A previous comparison using SHA256 hashes of materialized working-tree files
reported differences.

Those differences were caused by working-tree representation, such as LF/CRLF
line-ending conversion on Windows.

They did NOT represent corruption or loss of Git-versioned content.

Future Git restore verification must compare canonical Git objects:

1. commit ID;
2. tree ID;
3. tracked file list;
4. blob IDs.

Filesystem SHA256 comparisons may be used only when representation is known
to be identical.

## Scope

This verification proves recoverability of the Git-versioned contents of
C:\AADO.

It does NOT verify backup or recovery of:

- C:\AADO_PRIVATE
- Windows configuration
- installed software
- credentials
- runtime state
- the complete Rabisu VPS

Those require separate backup mechanisms.
