# JAVA SPECIFIC CI/CD Approach

The CI/CD pipeline in this project adheres to the principles outlined in the common-ci project, with the following exceptions:

## Environment

In Java Projects, we utilise a custom PowerShell script (setup-environment.ps1) to change Java JDK version instead of relying on the actions/setup-java within the YAML workflow file. This approach grants us more flexibility in terms of local testing, where we can switch between different java versions using the same approach. 
The Java SDK Versions that are pre-installed on the available runners are available here in the relevant READMEs: 

https://github.com/actions/runner-images/tree/main/images

The options.json file in java project repositories contains the environmental variable for the specified Java version e.g. "JAVA_HOME_8_X64". This option is then used as an input for the setup-environment script, which overwrites the JAVA_HOME variable and sets the desired Java version on the runner.

## Code Signing
Our Java APIs are packaged using Maven, and we sign the resulting packages as part of the build-package.ps1 script. The necessary files for signing are generated in the build-packages.ps1 script, which receives its content from GitHub secrets passed as parameters. Java package signing uses a PGP ASCII Armored File with the file extension .asc, instead of the .pfx format used in Dotnet. The gpg tool is used to import the .asc file as part of the signing process, after which the package is signed using the maven-gpg-plugin during the Maven deploy process.

## Deployment

In our projects, we've replaced the Maven Deploy Plugin with the Nexus Staging Maven Plugin for deploying packages. The plugin is configured in the parent pom.xml file. You can find more information on how to configure the project for deployment using this plugin [here](https://help.sonatype.com/repomanager2/staging-releases/configuring-your-project-for-deployment). 

Because the packages are built and tested in different jobs, the packages are uploaded as artifacts in the build job and downloaded in the test job.
The packages are then copied to and from two locations on the local machine: the local Maven repository in `{$user.home}/.m2/repository`, and the local Nexus staging repository in `{$user.home}/.m2/staging`. The location of the latter is specified in the altStagingDirectory element in the parent pom.xml file, as shown in the following snippet:

```
<plugin>
  <groupId>org.sonatype.plugins</groupId>
  <artifactId>nexus-staging-maven-plugin</artifactId>
  <version>${nexus-staging-maven-plugin.version}</version>
  <extensions>true</extensions>
  <configuration>
    <serverId>${publishrepository.id}</serverId>
    <nexusUrl>${ossrh.baseurl}</nexusUrl>
    <altStagingDirectory>${user.home}/.m2</altStagingDirectory>
  </configuration>
</plugin>
```
To build packages locally, we use the mvn deploy command with the -DskipRemoteStaging=true option, which ensures that packages are not deployed to a remote repository. Once the packages are built, the `publish-package-maven.ps1` script uses the `mvn nexus-staging:deploy-staged` command to stage the packages to the remote Nexus staging repository.
