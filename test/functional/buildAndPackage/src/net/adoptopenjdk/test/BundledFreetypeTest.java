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

package net.adoptopenjdk.test;

import org.testng.annotations.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Set;
import java.util.logging.Logger;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

import static net.adoptopenjdk.test.JdkPlatform.OperatingSystem;
import static org.testng.Assert.assertEquals;
import static org.testng.Assert.assertTrue;

/**
 * Freetype needs to be bundled on Windows and macOS but should not be present on Linux or AIX.
 *
 * @see <a href="https://github.com/AdoptOpenJDK/openjdk-build/issues/2133">AdoptOpenJDK enhancement request</a>
 */
@Test(groups = {"level.extended"})
public class BundledFreetypeTest {

    private static final Logger LOGGER = Logger.getLogger(BundledFreetypeTest.class.getName());

    private final JdkPlatform jdkPlatform = new JdkPlatform();

    @Test
    public void freetypeOnlyBundledOnWindowsAndMacOS() throws IOException {
        String testJdkHome = System.getenv("TEST_JDK_HOME");
        if (testJdkHome == null) {
            throw new AssertionError("TEST_JDK_HOME is not set");
        }

        Pattern freetypePattern = Pattern.compile("(.*)?libfreetype\\.(dll|dylib|so)$");
        Set<String> freetypeFiles = Files.walk(Paths.get(testJdkHome))
                .map(Path::toString)
                .filter(name -> freetypePattern.matcher(name).matches())
                .collect(Collectors.toSet());

        if (jdkPlatform.runsOn(OperatingSystem.MACOS) || jdkPlatform.runsOn(OperatingSystem.WINDOWS)) {
            assertTrue(freetypeFiles.size() > 0, "Expected libfreetype to be bundled but is not.");
        } else {
            LOGGER.info("Found freetype-related files: " + freetypeFiles.toString());
            assertEquals(freetypeFiles.size(), 0, "Expected libfreetype not to be bundled but it is.");
        }
    }
}