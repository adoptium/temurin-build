/*
 * ********************************************************************************
 * Copyright (c) 2021, 2024 Contributors to the Eclipse Foundation
 *
 * See the NOTICE file(s) with this work for additional
 * information regarding copyright ownership.
 *
 * This program and the accompanying materials are made
 * available under the terms of the Apache Software License 2.0
 * which is available at https://www.apache.org/licenses/LICENSE-2.0.
 *
 * SPDX-License-Identifier: Apache-2.0
 * ********************************************************************************
 */

package net.adoptium.test;

import static org.testng.Assert.assertEquals;
import static org.testng.Assert.assertTrue;

import java.io.IOException;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.logging.Logger;
import java.util.regex.Pattern;

import org.testng.annotations.BeforeTest;
import org.testng.annotations.Test;

import net.adoptium.test.JdkPlatform.Architecture;
import net.adoptium.test.JdkPlatform.OperatingSystem;

/**
 * Tests the availability of various features like garbage collectors, flight recorder, that need to be enabled via
 * command line flags.
 */
@Test(groups = {"level.extended"})
public class FeatureTests {

    private static final Logger LOGGER = Logger.getLogger(FeatureTests.class.getName());

    private final JdkVersion jdkVersion = new JdkVersion();

    private final JdkPlatform jdkPlatform = new JdkPlatform();

    private String testJdkHome = null;

    /**
     * Ensure TEST_JDK_HOME environment variable is set for every test in this class.
     */
    @BeforeTest
    public final void ensureTestJDKSet() {
        String tmpJdkHome = System.getenv("TEST_JDK_HOME");
        if (tmpJdkHome == null) {
            throw new AssertionError("TEST_JDK_HOME is not set");
        }
        this.testJdkHome = tmpJdkHome;
    }

    /**
     * Tests whether JEP 493 is enabled for Eclipse Temurin builds.
     *
     * @see <a href="https://openjdk.java.net/jeps/493">JEP 493: Linking Run-Time Images without JMODs</a>
     */
    @Test
    public void testLinkableRuntimeJDK24Plus() {
        // Only JDK 24 and better and temurin builds have this enabled
        if (jdkVersion.isNewerOrEqual(24) && isVendorAdoptium()) {
            List<String> command = new ArrayList<>();
            command.add(String.format("%s/bin/jlink", testJdkHome));
            command.add("-J-Duser.lang=en");
            command.add("--help");

            try {
                ProcessBuilder processBuilder = new ProcessBuilder(command);
                Process process = processBuilder.start();

                String stdout = StreamUtils.consumeStream(process.getInputStream());
                if (process.waitFor() != 0) {
                    throw new AssertionError("Could not run jlink --help");
                }
                String[] lines = stdout.split(Pattern.quote(System.lineSeparator()));
                boolean seenCapabilities = false;
                String capLine = "";
                for (int i = 0; i < lines.length; i++) {
                    if (lines[i].trim().startsWith("Capabilities:")) {
                        seenCapabilities = true;
                        continue; // skip Capabilities line
                    }
                    if (!seenCapabilities) {
                        continue;
                    }
                    if (seenCapabilities) {
                        capLine = lines[i].trim();
                        break;
                    }
                }
                LOGGER.info(String.format("Matched 'Capabilities:' line: %s", capLine));
                assertEquals(capLine, "Linking from run-time image enabled",
                             "jlink should have enabled run-time image link capability");
            } catch (InterruptedException | IOException e) {
                throw new RuntimeException("Failed to launch JVM", e);
            }
        }
    }

    /**
     * Tests whether basic jlink works using the default module path. The only
     * included module in the output image is {@code java.base}.
     */
    @Test
    public void testJlinkJdk11AndBetter() throws IOException {
        // Only JDK 11 (JDK 9, really) and better have jlink
        if (jdkVersion.isNewerOrEqual(11)) {
            Path output = Paths.get("java.base-image");
            ensureOutputDirectoryDeleted(output);
            List<String> command = new ArrayList<>();
            command.add(String.format("%s/bin/jlink", testJdkHome));
            command.add("--add-modules");
            command.add("java.base");
            command.add("--output");
            command.add(output.toString());
            command.add("--verbose");

            try {
                ProcessBuilder processBuilder = new ProcessBuilder(command);
                processBuilder.inheritIO();
                Process process = processBuilder.start();

                if (process.waitFor() != 0) {
                    throw new AssertionError("Basic jlink smoke test failed! " + command);
                }
                LOGGER.info("Basic jlink smoke test passed. Command was: " + command);
            } catch (InterruptedException | IOException e) {
                throw new RuntimeException("Failed to launch JVM", e);
            } finally {
                ensureOutputDirectoryDeleted(output);
            }
        }
    }

    private static void ensureOutputDirectoryDeleted(final Path path) throws IOException {
        if (Files.exists(path)) {
            deleteDirRecursively(path);
        }
    }

    private static void deleteDirRecursively(final Path path) throws IOException {
        Files.walkFileTree(path, new SimpleFileVisitor<Path>() {

            @Override
            public FileVisitResult postVisitDirectory(final Path dir, final IOException e) throws IOException {
                Files.delete(dir);
                return FileVisitResult.CONTINUE;
            }

            @Override
            public FileVisitResult visitFile(final Path file, final BasicFileAttributes attrs) throws IOException {
                if (Files.isDirectory(file)) {
                    // deleted in post-visit
                    return FileVisitResult.CONTINUE;
                }
                Files.delete(file);
                return FileVisitResult.CONTINUE;
            }
        });
    }

    private boolean isVendorAdoptium() {
        return System.getProperty("java.vendor", "").toLowerCase(Locale.US).contains("adoptium");
    }

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
        if (jdkVersion.isNewerOrEqual(19)
                || jdkVersion.isNewerOrEqualSameFeature(17, 0, 9)
                || jdkVersion.isNewerOrEqualSameFeature(11, 0, 23)) {
            if (jdkPlatform.runsOn(OperatingSystem.LINUX, Architecture.RISCV64)) {
                shouldBePresent = true;
            }
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
        if (jdkVersion.isNewerOrEqual(19) || jdkVersion.isNewerOrEqualSameFeature(17, 0, 9)) {
            if (jdkPlatform.runsOn(OperatingSystem.LINUX, Architecture.RISCV64)) {
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
            if (!jdkPlatform.runsOn(OperatingSystem.WINDOWS, Architecture.X64)
                && !jdkPlatform.runsOn(OperatingSystem.WINDOWS, Architecture.AARCH64)
            ) {
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
        boolean shouldBePresent = false;
        if (jdkVersion.isNewerOrEqual(11) || jdkVersion.isNewerOrEqualSameFeature(8, 0, 262)) {
            if (!jdkPlatform.runsOn(OperatingSystem.AIX) || jdkVersion.isNewerOrEqual(20)) {
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
