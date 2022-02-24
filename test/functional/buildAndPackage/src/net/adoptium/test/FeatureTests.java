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
import java.util.ArrayList;
import java.util.List;
import java.util.logging.Logger;

import static net.adoptium.test.JdkPlatform.Architecture;
import static net.adoptium.test.JdkPlatform.OperatingSystem;
import static org.testng.Assert.assertEquals;
import static org.testng.Assert.assertTrue;

/**
 * Tests the availability of various features like garbage collectors, flight recorder, that need to be enabled via
 * command line flags.
 */
@Test(groups = {"level.extended"})
public class FeatureTests {

    private static final Logger LOGGER = Logger.getLogger(FeatureTests.class.getName());

    private final JdkVersion jdkVersion = new JdkVersion();

    private final JdkPlatform jdkPlatform = new JdkPlatform();

    /**
     * Tests whether Shenandoah GC is available.
     * <p/>
     * Shenandoah GC was enabled by default with JDK 15 (JEP 379) and backported to 11.0.9.
     *
     * @see <a href="https://openjdk.java.net/jeps/379">JEP 379: Shenandoah: A Low-Pause-Time Garbage
     * Collector (Production)</a>
     * @see <a href="https://bugs.openjdk.java.net/browse/JDK-8250784">JDK-8250784 (Backport)</a>
     * @see <a href="https://wiki.openjdk.java.net/display/shenandoah/Main#Main-SupportOverview">Shenandoah Support
     * Overview</a>
     */
    @Test
    public void testShenandoahAvailable() {
        String testJdkHome = System.getenv("TEST_JDK_HOME");
        if (testJdkHome == null) {
            throw new AssertionError("TEST_JDK_HOME is not set");
        }

        boolean shouldBePresent = false;
        if ((jdkVersion.isNewerOrEqual(15) || jdkVersion.isNewerOrEqualSameFeature(11, 0, 9))) {
            if (jdkPlatform.runsOn(OperatingSystem.LINUX, Architecture.AARCH64)
                    || jdkPlatform.runsOn(OperatingSystem.LINUX, Architecture.X86)
                    || jdkPlatform.runsOn(OperatingSystem.LINUX, Architecture.X64)
                    || jdkPlatform.runsOn(OperatingSystem.MACOS, Architecture.X64)
                    || jdkPlatform.runsOn(OperatingSystem.MACOS, Architecture.AARCH64)
                    || jdkPlatform.runsOn(OperatingSystem.WINDOWS, Architecture.X86)
                    || jdkPlatform.runsOn(OperatingSystem.WINDOWS, Architecture.X64)
                    || jdkPlatform.runsOn(OperatingSystem.WINDOWS, Architecture.AARCH64)
            ) {
                shouldBePresent = true;
            }
        }
        if (jdkVersion.isNewerOrEqual(17) && jdkPlatform.runsOn(OperatingSystem.LINUX, Architecture.PPC64LE)) {
        	shouldBePresent = true;
        }

        LOGGER.info(String.format("Detected %s on %s, expect Shenandoah to be present: %s",
                jdkVersion, jdkPlatform, shouldBePresent));

        List<String> command = new ArrayList<>();
        command.add(String.format("%s/bin/java", testJdkHome));
        command.add("-XX:+UseShenandoahGC");
        command.add("-version");

        try {
            ProcessBuilder processBuilder = new ProcessBuilder(command);
            processBuilder.inheritIO();

            int retCode = processBuilder.start().waitFor();
            if (shouldBePresent) {
                assertEquals(retCode, 0, "Expected Shenandoah to be present but it is absent.");
            } else {
                assertTrue(retCode > 0, "Expected Shenandoah to be absent but it is present.");
            }
        } catch (InterruptedException | IOException e) {
            throw new RuntimeException("Failed to launch JVM", e);
        }
    }

    /**
     * Tests whether Z Garbage Collector is available.
     * <p/>
     * Z Garbage Collector was enabled by default with JDK 15 (JEP 377).
     *
     * @see <a href="https://openjdk.java.net/jeps/377">JEP 377: ZGC: A Scalable Low-Latency Garbage Collector
     * (Production)</a>
     */
    @Test
    public void testZGCAvailable() {
        String testJdkHome = System.getenv("TEST_JDK_HOME");
        if (testJdkHome == null) {
            throw new AssertionError("TEST_JDK_HOME is not set");
        }

        boolean shouldBePresent = false;
        if (jdkVersion.isNewerOrEqual(15)) {
            if (jdkPlatform.runsOn(OperatingSystem.LINUX, Architecture.AARCH64)
                    || jdkPlatform.runsOn(OperatingSystem.LINUX, Architecture.X64)
                    || jdkPlatform.runsOn(OperatingSystem.MACOS, Architecture.X64)
                    || jdkPlatform.runsOn(OperatingSystem.LINUX, Architecture.PPC64LE)
                    || jdkPlatform.runsOn(OperatingSystem.MACOS, Architecture.AARCH64)
                    /*
                     * Windows is disabled until we can get 2019 Visual Studio
                     * and O/S levels in Adoptium infrastructure
                     * TODO revert https://github.com/adoptium/temurin-build/pull/2767
                     */
                    // || jdkPlatform.runsOn(OperatingSystem.WINDOWS, Architecture.X64)
            ) {
                shouldBePresent = true;
            }
        }

        LOGGER.info(String.format("Detected %s on %s, expect ZGC to be present: %s",
                jdkVersion, jdkPlatform, shouldBePresent));

        List<String> command = new ArrayList<>();
        command.add(String.format("%s/bin/java", testJdkHome));
        command.add("-XX:+UseZGC");
        command.add("-version");

        try {
            ProcessBuilder processBuilder = new ProcessBuilder(command);
            processBuilder.inheritIO();

            int retCode = processBuilder.start().waitFor();
            if (!jdkPlatform.runsOn(OperatingSystem.WINDOWS, Architecture.X64)) {
                if (shouldBePresent) {
                    assertEquals(retCode, 0, "Expected ZGC to be present but it is absent.");
                } else {
                    assertTrue(retCode > 0, "Expected ZGC to be absent but it is present.");
                }
            } else {
                // TODO Windows is complicated because only later versions of Windows supports ZGC, we need to find a way to detect that.
                assertTrue(retCode >= 0, "Automatically passing test on Windows until we can revert https://github.com/adoptium/temurin-build/pull/2767");
            }
        } catch (InterruptedException | IOException e) {
            throw new RuntimeException("Failed to launch JVM", e);
        }
    }

    /**
     * Tests whether JDK Flight Recorder is available.
     * <p/>
     * JDK Flight recorder was added to JDK 11 (JEP 328) and backported to JDK 8u262.
     *
     * @see <a href="https://openjdk.java.net/jeps/328">JEP 328: Flight Recorder</a>
     * @see <a href="https://bugs.openjdk.java.net/browse/JDK-8223147>JDK-8223147 (backport to 8u262)</a>
     */
    @Test
    public void testJFRAvailable() {
        String testJdkHome = System.getenv("TEST_JDK_HOME");
        if (testJdkHome == null) {
            throw new AssertionError("TEST_JDK_HOME is not set");
        }
        boolean shouldBePresent = false;
        if (jdkVersion.isNewerOrEqual(11) || jdkVersion.isNewerOrEqualSameFeature(8, 0, 262)) {
            if (!jdkPlatform.runsOn(OperatingSystem.AIX)) {
                shouldBePresent = true;
            }
        }
        LOGGER.info(String.format("Detected %s on %s, expect JFR to be present: %s",
                jdkVersion, jdkPlatform, shouldBePresent));
        List<String> command = new ArrayList<>();
        command.add(String.format("%s/bin/java", testJdkHome));
        command.add("-XX:StartFlightRecording");
        command.add("-version");
        try {
            ProcessBuilder processBuilder = new ProcessBuilder(command);
            processBuilder.inheritIO();
            int retCode = processBuilder.start().waitFor();
            if (shouldBePresent) {
                assertEquals(retCode, 0, "Expected JFR to be present but it is absent.");
            } else {
                assertTrue(retCode > 0, "Expected JFR to be absent but it is present.");
            }
        } catch (InterruptedException | IOException e) {
            throw new RuntimeException("Failed to launch JVM", e);
        }
    }
}
