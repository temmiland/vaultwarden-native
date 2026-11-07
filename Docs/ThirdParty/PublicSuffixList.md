# Mozilla Public Suffix List

`Packages/AppModules/Sources/AutoFillData/Resources/public_suffix_list.dat` is a bundled copy
of the [Mozilla Public Suffix List](https://publicsuffix.org/list/). It is used only offline to
find registrable-domain boundaries for AutoFill URI matching; it is not used as DNS validation.

- Upstream repository: `https://github.com/publicsuffix/list`
- Pinned revision: `a179a48c465e818cfd8d626691cb317985da87fb`
- SHA-256: `7333192f818588d9d0044d27d67210c782acd6d87cf71f54a00dfa20a561cfc9`
- License: Mozilla Public License 2.0; the source file retains its upstream notice.
- Included sections: ICANN and PRIVATE domains. Private suffixes prevent suggesting a credential
  across unrelated tenants of a shared hosting domain.

To update deliberately, obtain and review an upstream commit, then run:

```sh
./Scripts/update-public-suffix-list.sh <40-character-commit-sha>
```

Review the resulting diff and SHA-256 output, update this revision, add regression fixtures for
newly relevant rules, and preserve the notice in `THIRD_PARTY_NOTICES.md` for every source release.
