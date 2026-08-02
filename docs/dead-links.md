# Dead links

Links found dead during the POS-523 doc-link 404 sweep (checked 2026-08-02). For each row the
link was removed from the referencing doc (see the "Removed?" column for exceptions).

| repo-relative-path | dead URL | referencing doc | HTTP status | Removed? |
|---|---|---|---|---|
| README.md:9 | https://postedapp.com/docs/ | README.md (Quick links) | 404 | yes |
| README.md:10 | https://postedapp.com/docs/sdk/ios/sdk-installation | README.md (Quick links) | 404 | yes |
| README.md:230 | https://postedapp.com/docs/ | README.md (Analytics) | 404 | yes |
| README.md:332 | https://github.com/thepostedapp/posted-sdk-android | README.md (Other platform SDKs) | 404 | yes |
| README.md:333 | https://github.com/thepostedapp/posted-sdk-flutter | README.md (Other platform SDKs) | 404 | yes |
| README.md:334 | https://github.com/thepostedapp/posted-sdk-react-native | README.md (Other platform SDKs) | 404 | yes |
| README.md:34 | https://github.com/thepostedapp/posted-sdk-ios | README.md (Swift Package Manager install snippet) | 404 | no — see note |

**Note on README.md:34:** this URL is the `.package(url:...)` coordinate inside the SPM code
sample, not a rendered hyperlink — deleting it would leave invalid Swift syntax with no working
replacement, since no live repo URL exists yet. It's already tracked inline via
`TODO(B7): repo URL finalizes when the GitHub org/repo rename (board-gated) lands.` Left in place
pending that rename; flagged to CTO for awareness rather than removed unilaterally.
