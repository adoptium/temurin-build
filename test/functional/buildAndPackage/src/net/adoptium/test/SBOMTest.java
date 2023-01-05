/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


package net.adoptium.test;

import java.io.File;
import java.util.ArrayList;
import java.util.List;

import org.junit.Rule;
import org.junit.Test;
import org.testcontainers.containers.Container;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.utility.DockerImageName;
import org.testcontainers.containers.BindMode;

import static org.assertj.core.api.Assertions.assertThat;

public class SBOMTest {

    public static final DockerImageName CYCLONEDX_CLI_IMAGE = DockerImageName.parse("cyclonedx/cyclonedx-cli");

    @Rule
    public GenericContainer<?> cyclonedxCli = new GenericContainer<>(CYCLONEDX_CLI_IMAGE)
            .withClasspathResourceMapping("./", "/app/sboms", BindMode.READ_ONLY);

    /**
     * Tests the validation of SBOM files.
     * @throws Exception if there is an error during the test
     */

    @Test
    public void testSBOMValidation() throws Exception {
        // Start the container
        cyclonedxCli.start();

        // Get a list of all .json files in the app/sboms folder
        File folder = new File("app/sboms");
        if (!folder.exists()) {
            folder.mkdir();
        }
        File[] listOfFiles = folder.listFiles((dir, name) -> name.endsWith(".json"));

        // Validate each SBOM file using the cyclonedx-cli command
        List<String> failedFiles = new ArrayList<>();
        if (listOfFiles != null) {
            for (File file : listOfFiles) {
                if (file != null) {
                    String sbomFileName = "/app/sboms/" + file.getName();
                    if (sbomFileName.endsWith(".json") && sbomFileName.contains("sbom") && !sbomFileName.contains("metadata")) {
                        Container.ExecResult result = cyclonedxCli.execInContainer("--user", "root", "cyclonedx-cli", "validate", "--input-file", sbomFileName, "--fail-on-errors");
                        if (result != null && result.getExitCode() != 0) {
                            failedFiles.add(file.getName());
                        }
                    }
                }
            }
        }

        // Assert that no files failed validation
        assertThat(failedFiles).isEmpty();

        // Stop the container
        cyclonedxCli.stop();
    }
}
