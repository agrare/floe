# Change Log
All notable changes to this project will be documented in this file.
This project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased]

## [0.15.0] - 2024-10-28
### Added
- Add WorkflowBase base class for Workflow ([#279](https://github.com/ManageIQ/floe/pull/279))
- Add tool for using the aws stepfunctions simulator ([#244](https://github.com/ManageIQ/floe/pull/244))
- Implement Map state ([#184](https://github.com/ManageIQ/floe/pull/184))
- Add Map State Tolerated Failure ([#282](https://github.com/ManageIQ/floe/pull/282))
- Run Map iterations in parallel up to MaxConcurrency ([#283](https://github.com/ManageIQ/floe/pull/283))
- Implement Parallel State ([#291](https://github.com/ManageIQ/floe/pull/291))

### Changed
- More granular compare_key and determine path at initialization time ([#274](https://github.com/ManageIQ/floe/pull/274))
- For Choice validation, use instance variables and not payload ([#277](https://github.com/ManageIQ/floe/pull/277))
- Return ExceedToleratedFailureThreshold if ToleratedFailureCount/Percentage is present ([#285](https://github.com/ManageIQ/floe/pull/285))

### Fixed
- Fix case on log messages ([#280](https://github.com/ManageIQ/floe/pull/280))
- Handle either ToleratedFailureCount or ToleratedFailurePercentage ([#284](https://github.com/ManageIQ/floe/pull/284))

## [0.14.0] - 2024-08-20
### Added
- Implement "IsNumeric": false ([#266](https://github.com/ManageIQ/floe/pull/266))
- Support choices that do not have a Default defined ([#267](https://github.com/ManageIQ/floe/pull/267))
- Label containers/pods with workflow Execution ID ([#268](https://github.com/ManageIQ/floe/pull/268))
- Allow for Execution Id to be passed in ([#269](https://github.com/ManageIQ/floe/pull/269))

## [0.13.1] - 2024-08-16
### Fixed
- Fix podman/docker container_ref trailing newline ([#265](https://github.com/ManageIQ/floe/pull/265))

### Changed
- Improve type check for States.Hash ([#261](https://github.com/ManageIQ/floe/pull/261))
- Use Numeric over Integer || Float ([#264](https://github.com/ManageIQ/floe/pull/264))
- In ChoiceRule::Data, parse compare key and variable ([#257](https://github.com/ManageIQ/floe/pull/257))

## [0.13.0] - 2024-08-12
### Added
- Choice rule payload validation path ([#253](https://github.com/ManageIQ/floe/pull/253))
- Intrinsics JsonToString and StringToJson ([#256](https://github.com/ManageIQ/floe/pull/256))
- Add States.Format intrinsic function ([#258](https://github.com/ManageIQ/floe/pull/258))
- Intrinsics States.JsonMerge ([#255](https://github.com/ManageIQ/floe/pull/255))
- Enable support for Hashes in States.Hash ([#260](https://github.com/ManageIQ/floe/pull/260))

## [0.12.0] - 2024-07-31
### Added
- Set Floe.logger.level if DEBUG env var set ([#234](https://github.com/ManageIQ/floe/pull/234))
- Add InstrinsicFunction foundation + States.Array, States.UUID ([#194](https://github.com/ManageIQ/floe/pull/194))
- Evaluate IntrinsicFunctions from PayloadTemplate ([#236](https://github.com/ManageIQ/floe/pull/236))
- Add more intrinsic functions ([#242](https://github.com/ManageIQ/floe/pull/242))
- Add State#cause_path, error_path ([#249](https://github.com/ManageIQ/floe/pull/249))
- Validate Catcher Next ([#250](https://github.com/ManageIQ/floe/pull/250))
- Add spec/supports ([#248](https://github.com/ManageIQ/floe/pull/248))

### Fixed
- Handle non-hash input/output values ([#214](https://github.com/ManageIQ/floe/pull/214))
- Fix Input/Output handling for Pass, Choice, Succeed states ([#225](https://github.com/ManageIQ/floe/pull/225))
- Wrap Parslet::ParseFailed errors as Floe::InvalidWorkflowError ([#235](https://github.com/ManageIQ/floe/pull/235))
- Fix edge cases with States.Array ([#237](https://github.com/ManageIQ/floe/pull/237))
- Fix sporadic test failure with Wait state ([#243](https://github.com/ManageIQ/floe/pull/243))
- Fix invalid container names after normalizing ([#252](https://github.com/ManageIQ/floe/pull/252))

### Changed
- Extract ErrorMatcherMixin from Catch and Retry ([#186](https://github.com/ManageIQ/floe/pull/186))
- Output should be JSON ([#230](https://github.com/ManageIQ/floe/pull/230))
- Normalize functions to all take arguments ([#238](https://github.com/ManageIQ/floe/pull/238))
- Pass full path name to State.new for better errors ([#229](https://github.com/ManageIQ/floe/pull/229))
- Validate that state machine input is valid JSON ([#227](https://github.com/ManageIQ/floe/pull/227))
- Move the Parslet parse into initialize so that invalid function definition will fail on workflow load ([#245](https://github.com/ManageIQ/floe/pull/245))

## [0.11.3] - 2024-06-20
### Fixed
- ResultPath=$ replaces complete output ([#199](https://github.com/ManageIQ/floe/pull/199))
- Fix retrier backoff values ([#200](https://github.com/ManageIQ/floe/pull/200))
- Fix Retry issues ([#202](https://github.com/ManageIQ/floe/pull/202))
- Add Apache-2.0 license ([#217](https://github.com/ManageIQ/floe/pull/217))

### Changed
- Update gemspec summary ([#205](https://github.com/ManageIQ/floe/pull/205))
- Simpler State#long_name ([#204](https://github.com/ManageIQ/floe/pull/204))
- State only modifies Context#state - prep for Map/Parallel ([#206](https://github.com/ManageIQ/floe/pull/206))
- Set StateHistory in Workflow not State ([#211](https://github.com/ManageIQ/floe/pull/211))
- Make Runner#wait optional ([#190](https://github.com/ManageIQ/floe/pull/190))
- Pass credentials around with context ([#203](https://github.com/ManageIQ/floe/pull/203))
- Pass context to State without workflow ([#216](https://github.com/ManageIQ/floe/pull/216))
- Move the guts of the CLI into a class for easy testing ([#220](https://github.com/ManageIQ/floe/pull/220))

### Added
- Set State PreviousStateGuid in StateHistory ([#208](https://github.com/ManageIQ/floe/pull/208))
- Add a codeclimate config file ([#224](https://github.com/ManageIQ/floe/pull/224))
- Add an Execution unique ID to Context ([#226](https://github.com/ManageIQ/floe/pull/226))

## [0.11.2] - 2024-05-24
### Fixed
- Output now based upon raw input not effective input ([#191](https://github.com/ManageIQ/floe/pull/191))
- Fix error raised on invalid resource scheme ([#195](https://github.com/ManageIQ/floe/pull/195))

## [0.11.1] - 2024-05-20
### Fixed
- Fix issue where a failed state can leave a workflow in "running" ([#182](https://github.com/ManageIQ/floe/pull/182))

### Changed
- Drop unused Task#status ([#180](https://github.com/ManageIQ/floe/pull/180))
- Check task failed? in non_terminal_mixin ([#183](https://github.com/ManageIQ/floe/pull/183))

## [0.11.0] - 2024-05-02
### Fixed
- Ensure the local code is loaded in exe/floe ([#173](https://github.com/ManageIQ/floe/pull/173))
- Fix issues with exe/floe and various combinations of workflow and input ([#174](https://github.com/ManageIQ/floe/pull/174))

### Added
- Add support for pluggable schemes ([#169](https://github.com/ManageIQ/floe/pull/169))

### Changed
- Collapse some namespaces ([#171](https://github.com/ManageIQ/floe/pull/171))
- Pass workflow context into runner#run_async! ([#177](https://github.com/ManageIQ/floe/pull/177))

### Removed
- Remove unused run! method ([#176](https://github.com/ManageIQ/floe/pull/176))

## [0.10.0] - 2024-04-05
### Fixed
- Fix rubocops ([#164](https://github.com/ManageIQ/floe/pull/164))
- Output should contain errors ([#165](https://github.com/ManageIQ/floe/pull/165))

### Added
- Add simplecov ([#162](https://github.com/ManageIQ/floe/pull/162))
- Add ability to pass context on the command line ([#161](https://github.com/ManageIQ/floe/pull/161))
- Add specs for `Workflow#wait_until`, `#waiting?` ([#166](https://github.com/ManageIQ/floe/pull/166))

### Changed
- Drop non-standard Error/Cause fields ([#167](https://github.com/ManageIQ/floe/pull/167))

## [0.9.0] - 2024-02-19
### Changed
- Default to wait indefinitely ([#157](https://github.com/ManageIQ/floe/pull/157))
- Create docker runners factory and add scheme ([#152](https://github.com/ManageIQ/floe/pull/152))
- Add a watch method to Workflow::Runner for event driven updates ([#95](https://github.com/ManageIQ/floe/pull/95))

### Fixed
- Fix waiting on extremely short durations ([#160](https://github.com/ManageIQ/floe/pull/160))
- Fix wait state missing finish ([#159](https://github.com/ManageIQ/floe/pull/159))

## [0.8.0] - 2024-01-17
### Added
- Add CLI shorthand options for docker runner ([#147](https://github.com/ManageIQ/floe/pull/147))
- Run multiple workflows in exe/floe ([#149](https://github.com/ManageIQ/floe/pull/149))
- Add secure options for passing credentials via command-line ([#151](https://github.com/ManageIQ/floe/pull/151))
- Add a Docker Runner pull-policy option ([#155](https://github.com/ManageIQ/floe/pull/155))

### Fixed
- Fix podman with empty output ([#150](https://github.com/ManageIQ/floe/pull/150))
- Fix run_container logger saying docker when using podman ([#154](https://github.com/ManageIQ/floe/pull/154))
- Ensure that workflow credentials is not-nil ([#156](https://github.com/ManageIQ/floe/pull/156))

## [0.7.0] - 2023-12-18
### Changed
- Remove the dependency on more_core_extensions in ReferencePath ([#144](https://github.com/ManageIQ/floe/pull/144))

### Added
- Implement `ReferencePath#get` ([#144](https://github.com/ManageIQ/floe/pull/144))
- Allow a State to set a value in Credentials for subsequent states ([#145](https://github.com/ManageIQ/floe/pull/145))

## [0.6.1] - 2023-11-21
### Fixed
- Return an error payload if run_async! fails ([#143](https://github.com/ManageIQ/floe/pull/143))

### Changed
- Extract run_container_params for docker/podman ([#142](https://github.com/ManageIQ/floe/pull/142))

## [0.6.0] - 2023-11-09
### Added
- Prefix pod names with 'floe-' ([#132](https://github.com/ManageIQ/floe/pull/132))
- Validate that the workflow payload is correct ([#136](https://github.com/ManageIQ/floe/pull/136))

### Fixed
- Fix issue where certain docker image names cannot be pod names ([#134](https://github.com/ManageIQ/floe/pull/134))
- Fix uninitialized constant RSpec::Support::Differ in tests ([#137](https://github.com/ManageIQ/floe/pull/137))
- Handle ImagePullErr/ImagePullBackOff as errors ([#135](https://github.com/ManageIQ/floe/pull/135))

### Changed
- Add task spec helper ([#123](https://github.com/ManageIQ/floe/pull/123))
- Rename State#run_wait to just #wait ([#139](https://github.com/ManageIQ/floe/pull/139))
- Refactor the Podman runner to be a Docker subclass ([#140](https://github.com/ManageIQ/floe/pull/140))

## [0.5.0] - 2023-10-12
### Added
- For task errors, use the json on the last line ([#128](https://github.com/ManageIQ/floe/pull/128))
- Add ability to pass task service account to kube runner ([#131](https://github.com/ManageIQ/floe/pull/131))

### Fixed
- Don't put credentials file into input ([#124](https://github.com/ManageIQ/floe/pull/124))
- exe/floe return success status if the workflow was successful ([#129](https://github.com/ManageIQ/floe/pull/129))
- For error output, drop trailing newline ([#126](https://github.com/ManageIQ/floe/pull/126))

## [0.4.1] - 2023-10-06
### Added
- Add Fail#CausePath and Fail#ErrorPath ([#110](https://github.com/ManageIQ/floe/pull/110))
- Add Task#Retrier incremental backoff and Wait#Timestamp ([#100](https://github.com/ManageIQ/floe/pull/100))

### Fixed
- Combine stdout and stderr for docker and podman runners ([#104](https://github.com/ManageIQ/floe/pull/104))
- Don't raise an exception on task failure ([#115](https://github.com/ManageIQ/floe/pull/115))
- Fix task output handling ([#112](https://github.com/ManageIQ/floe/pull/112))
- Fix Context#input not JSON parsed ([#122](https://github.com/ManageIQ/floe/pull/122))

## [0.4.0] - 2023-09-26
### Added
- Add ability to run workflows asynchronously ([#52](https://github.com/ManageIQ/floe/pull/92))
- Add Workflow.wait, Workflow#step_nonblock, Workflow#step_nonblock_wait ([#92](https://github.com/ManageIQ/floe/pull/92))

## [0.3.1] - 2023-08-29
### Added
- Add more global podman runner options ([#90](https://github.com/ManageIQ/floe/pull/90))

## [0.3.0] - 2023-08-07
### Added
- Add --network=host option to Docker/Podman runners ([#81](https://github.com/ManageIQ/floe/pull/81))

### Fixed
- Fix PayloadTemplate value transformation rules ([#78](https://github.com/ManageIQ/floe/pull/78))
- Move end out of the root state node ([#80](https://github.com/ManageIQ/floe/pull/80))

## [0.2.3] - 2023-07-28
### Fixed
- Fix storing next_state in Context ([#76](https://github.com/ManageIQ/floe/pull/76))

## [0.2.2] - 2023-07-24
### Fixed
- Don't pick up real KUBECONFIG for tests ([#73](https://github.com/ManageIQ/floe/pull/73))
- Fix double json.parse and context default value ([#69](https://github.com/ManageIQ/floe/pull/69))

### Added
- Configure Renovate ([#46](https://github.com/ManageIQ/floe/pull/46))

### Changed
- Simplify next state handling ([#66](https://github.com/ManageIQ/floe/pull/66))
- Refactor Input/Output path handling ([#68](https://github.com/ManageIQ/floe/pull/68))

## [0.2.1] - 2023-07-12
### Fixed
- Fix State EnteredTime and FinishedTime ([#59](https://github.com/ManageIQ/floe/pull/59))

### Added
- Add workflow output ([#57](https://github.com/ManageIQ/floe/pull/57))

## [0.2.0] - 2023-07-05
### Added
- Add ability to pass options to `Floe::Workflow::Runner` ([#48](https://github.com/ManageIQ/floe/pull/48))
- Add kubeconfig file support to `Floe::Workflow::Runner::Kubernetes` ([#53](https://github.com/ManageIQ/floe/pull/53))

### Removed
- Remove to_dot/to_svg code ([#54](https://github.com/ManageIQ/floe/pull/54))

### Fixed
- Fixed default rake task to spec ([#55](https://github.com/ManageIQ/floe/pull/55))

## [0.1.1] - 2023-06-05
### Fixed
- Fix States::Wait Path initializer arguments ([#47](https://github.com/ManageIQ/floe/pull/47))

## [0.1.0] - 2023-03-13
### Added
- Initial release

[Unreleased]: https://github.com/ManageIQ/floe/compare/v0.14.0...HEAD
[0.14.0]: https://github.com/ManageIQ/floe/compare/v0.13.1...v0.14.0
[0.13.1]: https://github.com/ManageIQ/floe/compare/v0.13.0...v0.13.1
[0.13.0]: https://github.com/ManageIQ/floe/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/ManageIQ/floe/compare/v0.11.3...v0.12.0
[0.11.3]: https://github.com/ManageIQ/floe/compare/v0.11.2...v0.11.3
[0.11.2]: https://github.com/ManageIQ/floe/compare/v0.11.1...v0.11.2
[0.11.1]: https://github.com/ManageIQ/floe/compare/v0.11.0...v0.11.1
[0.11.0]: https://github.com/ManageIQ/floe/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/ManageIQ/floe/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/ManageIQ/floe/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/ManageIQ/floe/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/ManageIQ/floe/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/ManageIQ/floe/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/ManageIQ/floe/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/ManageIQ/floe/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/ManageIQ/floe/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/ManageIQ/floe/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/ManageIQ/floe/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/ManageIQ/floe/compare/v0.2.3...v0.3.0
[0.2.3]: https://github.com/ManageIQ/floe/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/ManageIQ/floe/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/ManageIQ/floe/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/ManageIQ/floe/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/ManageIQ/floe/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/ManageIQ/floe/tree/v0.1.0
