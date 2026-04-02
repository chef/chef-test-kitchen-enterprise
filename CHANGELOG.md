# Test Kitchen Change Log

<!-- usage documentation: https://expeditor.chef.io/docs/reference/changelog/#common-changelog -->
<!-- latest_release unreleased -->
## Unreleased

#### Merged Pull Requests
- shift image config to the right [#85](https://github.com/chef/chef-test-kitchen-enterprise/pull/85) ([rishichawda](https://github.com/rishichawda))
<!-- latest_release -->

<!-- release_rollup -->
### Changes not yet released to rubygems.org

#### Merged Pull Requests
- shift image config to the right [#85](https://github.com/chef/chef-test-kitchen-enterprise/pull/85) ([rishichawda](https://github.com/rishichawda)) <!-- 2.0.12 -->
- add arm build/upload and promotion pipeline [#84](https://github.com/chef/chef-test-kitchen-enterprise/pull/84) ([rishichawda](https://github.com/rishichawda)) <!-- 2.0.12 -->
<!-- release_rollup -->

<!-- latest_stable_release -->
## [v2.0.11](https://github.com/chef/chef-test-kitchen-enterprise/tree/v2.0.11) (2026-03-26)

#### Merged Pull Requests
- Rebranding Change and  the new version and change.log file [#11](https://github.com/chef/chef-test-kitchen-enterprise/pull/11) ([sanghinitin](https://github.com/sanghinitin))
- Kitchen init change [#13](https://github.com/chef/chef-test-kitchen-enterprise/pull/13) ([sanghinitin](https://github.com/sanghinitin))
- Include the Chef-cli as gem with the test-kitchen hab package [#14](https://github.com/chef/chef-test-kitchen-enterprise/pull/14) ([ashiqueps](https://github.com/ashiqueps))
- Updated the kitchen context approach with env variable [#15](https://github.com/chef/chef-test-kitchen-enterprise/pull/15) ([ashiqueps](https://github.com/ashiqueps))
- Updated the pkg description and Gemfile [#16](https://github.com/chef/chef-test-kitchen-enterprise/pull/16) ([ashiqueps](https://github.com/ashiqueps))
- Updated the error message and start message branding [#17](https://github.com/chef/chef-test-kitchen-enterprise/pull/17) ([ashiqueps](https://github.com/ashiqueps))
- added slack promot pipeline [#20](https://github.com/chef/chef-test-kitchen-enterprise/pull/20) ([sanghinitin](https://github.com/sanghinitin))
- Removing changelog pipeline [#21](https://github.com/chef/chef-test-kitchen-enterprise/pull/21) ([sanghinitin](https://github.com/sanghinitin))
- Removed hab test duplicate pipeline [#22](https://github.com/chef/chef-test-kitchen-enterprise/pull/22) ([sanghinitin](https://github.com/sanghinitin))
- [CHEF-18291] Habitat tests for the windows platform [#23](https://github.com/chef/chef-test-kitchen-enterprise/pull/23) ([ashiqueps](https://github.com/ashiqueps))
- CHEF-18535 - Updating channels and fixing workloads [#24](https://github.com/chef/chef-test-kitchen-enterprise/pull/24) ([nikhil2611](https://github.com/nikhil2611))
- Chef-18535 Build pipeline fix [#25](https://github.com/chef/chef-test-kitchen-enterprise/pull/25) ([nikhil2611](https://github.com/nikhil2611))
- CHEF-18535 Adding up HAB_BLDR_CHANNEL env  [#26](https://github.com/chef/chef-test-kitchen-enterprise/pull/26) ([nikhil2611](https://github.com/nikhil2611))
- CHEF-18535-Added back the env to the plan files to test the pipelines [#27](https://github.com/chef/chef-test-kitchen-enterprise/pull/27) ([nikhil2611](https://github.com/nikhil2611))
- Added back the env var and update the promote workload [#28](https://github.com/chef/chef-test-kitchen-enterprise/pull/28) ([nikhil2611](https://github.com/nikhil2611))
- Fixed the issue with loading the license config [#34](https://github.com/chef/chef-test-kitchen-enterprise/pull/34) ([ashiqueps](https://github.com/ashiqueps))
- [CHEF-18897] Add the berkshelf gem and use the chef-cli from the Chef-DKE [#36](https://github.com/chef/chef-test-kitchen-enterprise/pull/36) ([ashiqueps](https://github.com/ashiqueps))
- Rename the chef-dke to chef workstation [#40](https://github.com/chef/chef-test-kitchen-enterprise/pull/40) ([sanghinitin](https://github.com/sanghinitin))
- [CHEF-20238] Updated the kitchen license commands with usage info [#39](https://github.com/chef/chef-test-kitchen-enterprise/pull/39) ([ashiqueps](https://github.com/ashiqueps))
- Ruby upgrade 3.4 change [#43](https://github.com/chef/chef-test-kitchen-enterprise/pull/43) ([sanghinitin](https://github.com/sanghinitin))
- CHEF-21187- Ruby 3.4 update in chef-test-kitchen-enterprise hab package [#46](https://github.com/chef/chef-test-kitchen-enterprise/pull/46) ([nikhil2611](https://github.com/nikhil2611))
- Fixing habitat test builds by declaring HAB_ORIGIN after habitat install [#48](https://github.com/chef/chef-test-kitchen-enterprise/pull/48) ([nikhil2611](https://github.com/nikhil2611))
- Updating windows hab pkg to ruby 3.4 and fixing test pipeline [#47](https://github.com/chef/chef-test-kitchen-enterprise/pull/47) ([nikhil2611](https://github.com/nikhil2611))
- Replaced the usage of blank? with empty? [#50](https://github.com/chef/chef-test-kitchen-enterprise/pull/50) ([ashiqueps](https://github.com/ashiqueps))
- Cookstyle and testing fixes [#54](https://github.com/chef/chef-test-kitchen-enterprise/pull/54) ([Stromweld](https://github.com/Stromweld))
- [CHEF-23440] - Mandatory License enforcemnt on kitchen converge command [#55](https://github.com/chef/chef-test-kitchen-enterprise/pull/55) ([nikhil2611](https://github.com/nikhil2611))
- [CHEF-27321] - Skip license check when using internal/private registry [#59](https://github.com/chef/chef-test-kitchen-enterprise/pull/59) ([nikhil2611](https://github.com/nikhil2611))
- Updated the verify pipeline to private [#66](https://github.com/chef/chef-test-kitchen-enterprise/pull/66) ([ashiqueps](https://github.com/ashiqueps))
- Removal of chef provisioner to new gem plugin [#60](https://github.com/chef/chef-test-kitchen-enterprise/pull/60) ([Stromweld](https://github.com/Stromweld))
- Workflow to build and push gem to artifactory [#68](https://github.com/chef/chef-test-kitchen-enterprise/pull/68) ([ashiqueps](https://github.com/ashiqueps))
- [CHEF-28361] Integrate kitchen-plugins to chef-tke [#69](https://github.com/chef/chef-test-kitchen-enterprise/pull/69) ([ashiqueps](https://github.com/ashiqueps))
- lint roller change for grype scan  [#73](https://github.com/chef/chef-test-kitchen-enterprise/pull/73) ([sanghinitin](https://github.com/sanghinitin))
- Moving git dependency from package dep to build dep [#76](https://github.com/chef/chef-test-kitchen-enterprise/pull/76) ([nikhil2611](https://github.com/nikhil2611))
- Update Expeditor config to promote Habitat packages to current and base-2025 channels [#78](https://github.com/chef/chef-test-kitchen-enterprise/pull/78) ([nikhil2611](https://github.com/nikhil2611))
- Added the berkshelf to chef-tke [#79](https://github.com/chef/chef-test-kitchen-enterprise/pull/79) ([ashiqueps](https://github.com/ashiqueps))
- Onboarding sonarqube and enable blackduck scan [#67](https://github.com/chef/chef-test-kitchen-enterprise/pull/67) ([nikhil2611](https://github.com/nikhil2611))
- CHEF-29316- Create CODE_OF_CONDUCT.md file  [#62](https://github.com/chef/chef-test-kitchen-enterprise/pull/62) ([Saburesh07](https://github.com/Saburesh07))
- bump dokken driver and kitchen-chef-enterprise dep versions [#77](https://github.com/chef/chef-test-kitchen-enterprise/pull/77) ([Stromweld](https://github.com/Stromweld))
- Adding NOTICE file to the hab pkg [#75](https://github.com/chef/chef-test-kitchen-enterprise/pull/75) ([nikhil2611](https://github.com/nikhil2611))
<!-- latest_stable_release -->