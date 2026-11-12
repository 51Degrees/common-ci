# Environment variable names

This page is made from [`environment-variables.json`](environment-variables.json) by [`steps/environment-variables.ps1`](steps/environment-variables.ps1). Change the JSON file and run the script, never this page. The JSON file decides, and a test fails when this page differs from it.

These are the environment variable names that 51Degrees packages, tests, examples and CI scripts read, in every language. Each is a public name. A patch release never removes or renames one. When a name changes, the old name is still read for at least one release, only when the new name is unset or empty, with a message naming the new one.

Names that the operating system, GitHub Actions or a build tool defines, such as `CI`, `PATH`, `HOME` and the `GITHUB_`, `RUNNER_` and `CARGO_` names, are not 51Degrees names and are not listed.

## Current names

Every current name starts `_51DEGREES_`. "Packages" means a published package reads the name. "Tests, examples and CI" means only those do.

| Name | What it holds | Read by | Languages | Deprecated names |
| --- | --- | --- | --- | --- |
| `_51DEGREES_CLOUD_ENDPOINT` | The address of the 51Degrees cloud service to send requests to, in place of the public service. | Packages | .NET, Go, Java, Node.js, PHP, Python, Rust | `FOD_CLOUD_API_URL` (.NET, Go, Java, Node.js, PHP, Python, Rust), `51DEGREES_CLOUD_ENDPOINT` (.NET, Rust), `cloud_endpoint` (PHP, Python), `CLOUD_ENDPOINT` (Python), `FIFTYONE_CLOUD_ENDPOINT` (.NET), `51D_CLOUD_ENDPOINT` (.NET) |
| `_51DEGREES_CLOUD_REQUEST_ORIGIN` | The Origin header the cloud examples send, for a resource key that only accepts requests from listed origins. | Tests, examples and CI | Python | `cloud_request_origin` (Python) |
| `_51DEGREES_CXX_DIR` | The folder of a 51degrees-cxx source tree for the Rust -sys crates to build from, in place of the copy in the crate. | Packages | Rust | `FIFTYONE_CXX_DIR` (Rust) |
| `_51DEGREES_DD_PATH` | The path of a Device Detection data file (.hash) for tests and examples to use. | Tests, examples and CI | .NET, Go, Java, Node.js, PHP, Python, Rust | `51DEGREES_DD_PATH` (.NET, Java, Node.js, PHP, Python, Rust), `DEVICEDETECTIONDATAFILE` (.NET), `FIFTYONE_DATA_FILE` (PHP), `DATA_FILE` (Go), `DD_DATA_FILE` (Go) |
| `_51DEGREES_DEPRECATED_NAMES_CHILD_EXPECTS` | Set by a Rust test for the child process it starts, saying what the child should find. Nobody else needs to set it. | Tests, examples and CI | Rust |  |
| `_51DEGREES_DERIVED_PROPERTIES_COMMIT` | The commit of the derived-properties repository the Rust crate was built from. Its build script sets it, so nobody else needs to. | Packages | Rust |  |
| `_51DEGREES_EVIDENCE_YAML` | The path of a YAML file of evidence for the examples to process. | Tests, examples and CI | Go | `EVIDENCE_YAML` (Go) |
| `_51DEGREES_EXAMPLE_HTTPS_PORTS` | The HTTPS ports the .NET web examples listen on. | Tests, examples and CI | .NET |  |
| `_51DEGREES_EXAMPLE_HTTP_PORTS` | The HTTP ports the .NET web examples listen on. | Tests, examples and CI | .NET |  |
| `_51DEGREES_IPI_DATA_FILE_URL` | The address the IP Intelligence examples download a data file from when they update it. | Tests, examples and CI | Go | `IPI_DATA_FILE_URL` (Go) |
| `_51DEGREES_IPI_ENTERPRISE_SHARE` | A folder of dated IP Intelligence Enterprise data files, from which tests and examples take the newest. | Tests, examples and CI | Rust | `51DEGREES_IPI_ENTERPRISE_SHARE` (Rust) |
| `_51DEGREES_IPI_MEMORY_PROFILES` | The performance profiles the IP Intelligence memory test measures, separated by commas. Every profile is measured when it is not set. | Tests, examples and CI | Rust |  |
| `_51DEGREES_IPI_PATH` | The path of an IP Intelligence data file (.ipi) for tests and examples to use. The PHP IP Intelligence package also looks beside it for the Translations folder. | Packages | C and C++, .NET, Go, Java, Node.js, PHP, Python, Rust | `51DEGREES_IPI_PATH` (C and C++, .NET, Java, Node.js, Rust), `IPINTELLIGENCEDATAFILE` (.NET, PHP, Python), `DATA_FILE` (Go) |
| `_51DEGREES_LICENSE_KEY` | A licence key, for data file updates and for 51Did requests that need one. | Tests, examples and CI | .NET, Go, Java, Node.js, PHP, Python, Rust | `LICENSE_KEY` (.NET, Go, Java, Node.js, PHP, Python), `license_key` (Python), `DEVICE_DETECTION_KEY` (Go), `IPI_KEY` (Go), `51DEGREES_LICENSE_KEY` (Rust) |
| `_51DEGREES_LICENSE_KEY_51DID` | A licence key for the 51Did live tests. | Tests, examples and CI | .NET, Node.js, Rust |  |
| `_51DEGREES_LICENSE_KEY_BESPOKE` | A licence key that carries the CloudV5Bespoke product, for live cloud tests. | Tests, examples and CI | Java, Rust |  |
| `_51DEGREES_LICENSE_KEY_CLOUDV5BESPOKE` | A licence key that carries the CloudV5Bespoke product, for live cloud tests. Java reads it after _51DEGREES_LICENSE_KEY_BESPOKE. | Tests, examples and CI | Java |  |
| `_51DEGREES_REQUIRE_ENTERPRISE` | When set, tests that need an IP Intelligence Enterprise data file fail rather than skip without one. | Tests, examples and CI | Rust |  |
| `_51DEGREES_REQUIRE_LOCATION` | When set, tests that need location properties fail rather than skip when the IP Intelligence data file has none. | Tests, examples and CI | Rust |  |
| `_51DEGREES_REQUIRE_TAC` | When set, tests that need the TAC and NativeModel properties fail rather than skip when the Device Detection data file lacks them. | Tests, examples and CI | Rust |  |
| `_51DEGREES_RESOURCE_KEY` | A resource key for the 51Degrees cloud service, for tests and examples. When it is unset, the .NET examples take the first variable, in name order, whose name starts _51DEGREES_RESOURCE_KEY, such as one for each data tier. | Tests, examples and CI | .NET, Go, Java, Node.js, PHP, Python, Rust | `RESOURCE_KEY` (.NET, Java, Node.js, PHP, Python), `resource_key` (PHP, Python), `51DEGREES_RESOURCE_KEY` (.NET, Java, Node.js, Rust), `SUPER_RESOURCE_KEY` (.NET, Java), `51D_RESOURCE_KEY` (.NET) |
| `_51DEGREES_RESOURCE_KEY_51DID` | A resource key for the 51Did live tests and examples. | Tests, examples and CI | .NET, Rust |  |
| `_51DEGREES_RESOURCE_KEY_ACCEPTCH_BROWSER` | A resource key for the Accept-CH tests, whose properties need the browser client hints. | Tests, examples and CI | PHP | `AcceptChBrowserKey` (PHP) |
| `_51DEGREES_RESOURCE_KEY_ACCEPTCH_HARDWARE` | A resource key for the Accept-CH tests, whose properties need the hardware client hints. | Tests, examples and CI | PHP | `AcceptChHardwareKey` (PHP) |
| `_51DEGREES_RESOURCE_KEY_ACCEPTCH_NONE` | A resource key for the Accept-CH tests, whose properties need no client hints. | Tests, examples and CI | PHP | `AcceptChNoneKey` (PHP) |
| `_51DEGREES_RESOURCE_KEY_ACCEPTCH_PLATFORM` | A resource key for the Accept-CH tests, whose properties need the platform client hints. | Tests, examples and CI | PHP | `AcceptChPlatformKey` (PHP) |
| `_51DEGREES_RESOURCE_KEY_BASIC` | A resource key on the basic data tier, for tests of what that tier can and cannot read. | Tests, examples and CI | .NET, Rust |  |
| `_51DEGREES_RESOURCE_KEY_BESPOKE` | A resource key that carries the CloudV5Bespoke product, for live cloud tests. | Tests, examples and CI | .NET, Java, Node.js, Python, Rust |  |
| `_51DEGREES_RESOURCE_KEY_BROWSER` | A resource key for the Accept-CH tests, whose properties need the browser client hints. | Tests, examples and CI | Node.js | `TEST_BROWSER_RESOURCE_KEY` (Node.js) |
| `_51DEGREES_RESOURCE_KEY_HARDWARE` | A resource key for the Accept-CH tests, whose properties need the hardware client hints. | Tests, examples and CI | Node.js | `TEST_HARDWARE_RESOURCE_KEY` (Node.js) |
| `_51DEGREES_RESOURCE_KEY_NO_SETHEADER` | A resource key for the Accept-CH tests, whose properties need no client hints. | Tests, examples and CI | Node.js | `TEST_NO_SETHEADER_RESOURCE_KEY` (Node.js) |
| `_51DEGREES_RESOURCE_KEY_PLATFORM` | A resource key for the Accept-CH tests, whose properties need the platform client hints. | Tests, examples and CI | Node.js | `TEST_PLATFORM_RESOURCE_KEY` (Node.js) |
| `_51DEGREES_RESOURCE_KEY_SUPER` | A resource key that carries every property, for tests. | Tests, examples and CI | Node.js | `TEST_SUPER_RESOURCE_KEY` (Node.js) |
| `_51DEGREES_RUN_PERFORMANCE_TESTS` | When set, the Python example tests also run the performance examples. | Tests, examples and CI | Python | `run_performance_tests` (Python) |
| `_51DEGREES_RUSTC_VERSION` | The version of the Rust compiler, which usage sharing reports as the language version. The crate's build script sets it, so nobody else needs to. | Packages | Rust |  |
| `_51DEGREES_TEST_BOTH` | A name the PHP environment variable tests set and read back to test the reader. Nobody else needs to set it. | Tests, examples and CI | PHP |  |
| `_51DEGREES_TEST_EMPTY` | A name the PHP environment variable tests set and read back to test the reader. Nobody else needs to set it. | Tests, examples and CI | PHP |  |
| `_51DEGREES_TEST_FILTER` | A filter that limits which .NET tests the CI scripts run. | Tests, examples and CI | .NET | `FIFTYONE_TEST_FILTER` (.NET) |
| `_51DEGREES_TEST_NAMED_KEY` | A name the test of the Python shared key helper sets and reads back. Nobody else needs to set it. | Tests, examples and CI | Python |  |
| `_51DEGREES_TEST_NEITHER` | A name the PHP environment variable tests set and read back to test the reader. Nobody else needs to set it. | Tests, examples and CI | PHP |  |
| `_51DEGREES_TEST_ONCE` | A name the PHP environment variable tests set and read back to test the reader. Nobody else needs to set it. | Tests, examples and CI | PHP |  |
| `_51DEGREES_TEST_PLACEHOLDER` | A name the PHP environment variable tests set and read back to test the reader. Nobody else needs to set it. | Tests, examples and CI | PHP |  |
| `_51DEGREES_TEST_UNSET` | A name the PHP environment variable tests set and read back to test the reader. Nobody else needs to set it. | Tests, examples and CI | PHP |  |
| `_51DEGREES_TRANSLATIONS_DIR` | The folder of IP Intelligence translation files the Rust crate builds in. Its build script sets it, so nobody else needs to. | Packages | Rust |  |
| `_51DEGREES_UA_CSV` | The path of a CSV file of User-Agents for the PHP fork safety test. | Tests, examples and CI | PHP | `FIFTYONE_UA_CSV` (PHP) |
| `_51DEGREES_WEB_ETAG_CHILD` | Set by a web test for the child process it starts, so the child knows its part. Nobody else needs to set it. | Tests, examples and CI | Go, Rust |  |

## Deprecated names

Each deprecated name is shown with the languages that read it in place of the current name. A release is shown where it has been decided which release stops reading the name.

The list holds 40 deprecated names, and no release has been decided yet for any of them to stop being read.

## Other names

These names do not start `_51DEGREES_`, and 51Degrees files read them. Each is a public name all the same.

| Name | What it holds | Set by | Languages |
| --- | --- | --- | --- |
| `ACCEPTCH_BROWSER_KEY` | A resource key for the .NET Accept-CH tests, whose properties need the browser client hints. | The .NET CI scripts | .NET |
| `ACCEPTCH_HARDWARE_KEY` | A resource key for the .NET Accept-CH tests, whose properties need the hardware client hints. | The .NET CI scripts | .NET |
| `ACCEPTCH_NONE_KEY` | A resource key for the .NET Accept-CH tests, whose properties need no client hints. | The .NET CI scripts | .NET |
| `ACCEPTCH_PLATFORM_KEY` | A resource key for the .NET Accept-CH tests, whose properties need the platform client hints. | The .NET CI scripts | .NET |
| `API_KEY` | The NuGet key the .NET publish workflow passes to common-ci. | The workflow step that reads it, from its own env block | .NET |
| `CLOUD_ROOT_URL` | The address of the cloud service the browser test suite checks the examples against. | The shared browser test suite in 51Degrees/selenium-api-tests, which every language's CI starts | .NET, Java, Node.js, PHP, Python, Rust |
| `COMMON_CI` | The folder of a common-ci checkout that is not beside the repository, for the CI scripts that use its steps, and their tests. | Whoever runs those scripts outside the shared workflows | .NET, Python |
| `DATA_FILES` | The names of the data files a Rust workflow step fetches, one to a line. | The workflow step that reads it, from its own env block | Rust |
| `DEVICEDETECTIONLICENSEKEY_DOTNET` | A licence key for the .NET Device Detection data file update tests. | The .NET CI scripts | .NET |
| `DEVICE_DETECTION_KEY` | A licence key the Rust examples workflow reads to download the Device Detection data file. | The workflow step that reads it, from its own env block | Rust |
| `DEVICE_DETECTION_URL` | The address the Rust examples workflow downloads the Device Detection data file from. | The workflow step that reads it, from its own env block | Rust |
| `directory` | The folder the Node.js examples and tests find their files from. The example tests set it to the example's own folder, and each reader uses its own folder when it is unset. | The Node.js example tests, or whoever runs an example | Node.js |
| `EXAMPLE_LANG` | The language of the example under test, for the browser test suite. | The shared browser test suite in 51Degrees/selenium-api-tests, which every language's CI starts | .NET, Java, Node.js, PHP, Python, Rust |
| `EXAMPLE_URL` | The address of the running example the browser test suite opens. | The shared browser test suite in 51Degrees/selenium-api-tests, which every language's CI starts | .NET, Java, Node.js, PHP, Python, Rust |
| `FIFTYONE_AGENT_SIGNATURE_NETWORK_TESTS` | Set to 1 to let the .NET agent signature tests reach the network. | Whoever runs those tests | .NET |
| `FIFTYONE_WRAPPER` | The path of a wrapper file the PHP fork safety test used to load. The file has gone, so the test only reports that the name is deprecated and nothing replaces it. | Whoever runs that test | PHP |
| `FROM_FORK` | Whether the pull request comes from a fork, for the Rust examples workflow. | The workflow step that reads it, from its own env block | Rust |
| `IPINTELLIGENCELICENSEKEY_DOTNET` | A licence key for the .NET IP Intelligence data file update tests. | The .NET CI scripts | .NET |
| `LicenseKey` | A licence key for the Java and Node.js data file update examples, read as LicenseKey and then as LICENSEKEY. | Whoever runs those examples | Java, Node.js |
| `LICENSEKEY` | A licence key for the Java and Node.js data file update examples, read when LicenseKey is unset. | Whoever runs those examples | Java, Node.js |
| `MODE` | Whether a Rust examples workflow job runs the on-premise or the cloud examples. | The workflow step that reads it, from its own env block | Rust |
| `PAID_RESOURCE_KEY` | A resource key on a paid data tier, for the browser test suite. | The shared browser test suite in 51Degrees/selenium-api-tests, which every language's CI starts | .NET, Java, Node.js, PHP, Python, Rust |
| `PATHS` | The data file paths the Rust restore-data-files action restores, one to a line. | The workflow step that reads it, from its own env block | Rust |
| `PipelineOptions__Elements__0__BuildParameters__DataFile` | The data file the .NET performance web example loads, as an ASP.NET Core configuration setting. | The .NET CI scripts | .NET |
| `PORT` | The port the example under test listens on, for the browser test suite. | The shared browser test suite in 51Degrees/selenium-api-tests, which every language's CI starts | .NET, Java, Node.js, PHP, Python, Rust |
| `RESOURCE_KEY_CLOUD_V5_BESPOKE` | A resource key that carries the CloudV5Bespoke product, set by the .NET CI scripts. | The .NET CI scripts | .NET |
| `ROOT` | The folder the Rust restore-data-files action restores data files into. | The workflow step that reads it, from its own env block | Rust |
| `SELENIUM_TESTS_REF` | The branch of 51Degrees/selenium-api-tests the Java CI checks out. | Whoever runs the Java CI scripts | Java |
| `SKIP_WEB_PERFORMANCE` | When true, the .NET performance script leaves out the web performance test. | Whoever runs the .NET performance script | .NET |
| `SPIN` | The path of the spin command for the Rust WebAssembly host test. | Whoever runs that test | Rust |
| `SuperResourceKey` | A resource key for the Java TAC and native model cloud examples and the Geo-Location tests, read as an environment variable or a system property, and by the examples under its upper case name as well. | Whoever runs those examples or tests | Java |
| `SUPERRESOURCEKEY` | A resource key for the Java TAC and native model cloud examples, read when SuperResourceKey is unset. | Whoever runs those examples | Java |
| `SWIG_VERSION` | The SWIG version the PHP wrapper check workflow builds. | The workflow step that reads it, from its own env block | PHP |
| `TestCloudEndpoint` | The cloud endpoint that the Java Device Detection web cloud example's options file names, read as TestCloudEndpoint, then TESTCLOUDENDPOINT, then as a system property. | The Java CI scripts, or whoever runs that example | Java |
| `TestCloudEndPoint` | The cloud endpoint for the Java IP Intelligence cloud console examples, read as TestCloudEndPoint, then TESTCLOUDENDPOINT, then as a system property. | Whoever runs those examples | Java |
| `TESTCLOUDENDPOINT` | The cloud endpoint for the Java cloud examples, read when TestCloudEndpoint or TestCloudEndPoint is unset. | Whoever runs those examples | Java |
| `TestDataFile` | A Device Detection data file for the Java on-premise examples, which their options files name, read as TestDataFile, then TESTDATAFILE, then as a system property. | Whoever runs those examples or their tests | Java |
| `TESTDATAFILE` | A Device Detection data file for the Java on-premise examples, read when TestDataFile is unset. | Whoever runs those examples or their tests | Java |
| `TestDeviceDetectionDataFile` | A Device Detection data file that the Java IP Intelligence mixed examples' options files name, read as TestDeviceDetectionDataFile, then TESTDEVICEDETECTIONDATAFILE, then as a system property. | Whoever runs those examples | Java |
| `TESTDEVICEDETECTIONDATAFILE` | A Device Detection data file for the Java IP Intelligence mixed examples, read when TestDeviceDetectionDataFile is unset. | Whoever runs those examples | Java |
| `TestLicenseKey` | A licence key for the Java live cloud tests, read after the _51DEGREES_ names. | Whoever runs the Java tests | Java |
| `TestResourceKey` | A resource key for the Java cloud tests and examples, read as an environment variable or a system property, and by the examples and their options files under its upper case name as well. | Whoever runs the Java tests or examples | Java |
| `TESTRESOURCEKEY` | A resource key for the Java cloud tests and examples, read when TestResourceKey is unset. | Whoever runs the Java tests or examples | Java |
| `VERSION` | The version the Rust publish workflow is releasing. | The workflow step that reads it, from its own env block | Rust |

## Languages

| Language | Repository |
| --- | --- |
| C and C++ | [51Degrees/51degrees-cxx](https://github.com/51Degrees/51degrees-cxx) |
| .NET | [51Degrees/51degrees-dotnet](https://github.com/51Degrees/51degrees-dotnet) |
| Go | [51Degrees/51degrees-go](https://github.com/51Degrees/51degrees-go) |
| Java | [51Degrees/51degrees-java](https://github.com/51Degrees/51degrees-java) |
| Node.js | [51Degrees/51degrees-node](https://github.com/51Degrees/51degrees-node) |
| PHP | [51Degrees/51degrees-php](https://github.com/51Degrees/51degrees-php) |
| Python | [51Degrees/51degrees-python](https://github.com/51Degrees/51degrees-python) |
| Rust | [51Degrees/51degrees-rust](https://github.com/51Degrees/51degrees-rust) |

## Changing the list

1. Change `environment-variables.json`.
2. Run `pwsh steps/environment-variables.ps1`, which checks the list and writes this page.
3. Commit both files together.

The tests in `steps/environment-variables.Tests.ps1` fail when the list breaks a rule or this page differs from it.
