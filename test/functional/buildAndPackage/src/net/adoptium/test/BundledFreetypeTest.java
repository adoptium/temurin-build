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

import org.testng.annotations.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Set;
import java.util.logging.Logger;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

import static net.adoptium.test.JdkPlatform.OperatingSystem;
import static net.adoptium.test.JdkVersion.VM;
import static org.testng.Assert.assertEquals;
import static org.testng.Assert.assertTrue;

/**
 * Freetype needs to be bundled on Windows and macOS
 * but should not be present on Linux or AIX.
 *
 * @see <a href="https://github.com/adoptium/temurin-build/issues/2133">
 * Adoptium enhancement request</a>
 */
@Test(groups = {"level.extended"})
public class BundledFreetypeTest {

    /**
     * Message logger for test debug output.
     */
    private static final Logger LOGGER
        = Logger.getLogger(BundledFreetypeTest.class.getName());

    /**
     * This is used to identify the OS we're running on.
     */
    private final JdkPlatform jdkPlatform = new JdkPlatform();

    /**
     * This is used to identify the JDK version we're using.
     */
    private final JdkVersion jdkVersion = new JdkVersion();

    /**
     * Test to ensure freetype is bundled with this build
     * or not, depending on the platform & JDK version.
     */
    @Test
    public void freetypeOnlyBundledOnCertainPlatforms() throws IOException {
        String testJdkHome = System.getenv("TEST_JDK_HOME");
        if (testJdkHome == null) {
            throw new AssertionError("TEST_JDK_HOME is not set");
        }

        Pattern freetypePattern
            = Pattern.compile("(.*)?freetype(\\.(\\d)+)?\\.(dll|dylib|so)$");
        Set<String> freetypeFiles = Files.walk(Paths.get(testJdkHome))
                .map(Path::toString)
                .filter(name -> freetypePattern.matcher(name).matches())
                .collect(Collectors.toSet());

        if (jdkVersion.isNewerOrEqual(21)) {
            // jdk-21+ uses "bundled" FreeType
            assertTrue(freetypeFiles.size() > 0,
              "Expected libfreetype.dylib to be bundled but it is not.");
        } else if (jdkPlatform.runsOn(OperatingSystem.MACOS)) {
            assertTrue(freetypeFiles.size() > 0,
              "Expected libfreetype.dylib to be bundled but it is not.");
        } else if (jdkPlatform.runsOn(OperatingSystem.WINDOWS)) {
            assertTrue(freetypeFiles.size() > 0,
              "Expected freetype.dll to be bundled, but it is not.");
        } else if (jdkPlatform.runsOn(OperatingSystem.AIX)
                && (jdkVersion.isNewerOrEqual(13) || (jdkVersion.usesVM(VM.OPENJ9) && jdkVersion.isNewerOrEqual(8)))) {
            assertTrue(freetypeFiles.size() > 0,
              "Expected libfreetype.so to be bundled, but it is not.");
        } else {
            LOGGER.info("Found freetype-related files: "
                        + freetypeFiles.toString());
            assertEquals(freetypeFiles.size(), 0,
              "Expected libfreetype not to be bundled but it is.");
        }
    }
}
