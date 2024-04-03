/*
 * ********************************************************************************
 * Copyright (c) 2021 Contributors to the Eclipse Foundation
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

import org.testng.annotations.Test;

import java.io.IOException;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

import static net.adoptium.test.JdkVersion.VM;
import static org.testng.Assert.assertEquals;
import static org.testng.Assert.assertNotEquals;
import static org.testng.Assert.assertTrue;
import static org.testng.Assert.assertFalse;

/**
 * Tests whether vendor names and correct URLs appear in all the places they are supposed to.
 */
@Test(groups = {"level.extended"})
public class VendorPropertiesTest {

    /**
     * The checks for a given vendor.
     */
    private final VmPropertiesChecks vendorChecks;

    /**
     * Class tells us what the jdk version and vm type is.
     */
    private static final JdkVersion JDK_VERSION = new JdkVersion();

    /**
     * Constructor method.
     */
    public VendorPropertiesTest() {
        Set<VmPropertiesChecks> allPropertiesChecks = new LinkedHashSet<>();
        allPropertiesChecks.add(new AdoptiumPropertiesChecks());
        allPropertiesChecks.add(new SemeruPropertiesChecks());
        allPropertiesChecks.add(new CorrettoPropertiesChecks());

        // TODO: Somehow obtain the vendor name from the outside. Using any JVM properties is not a solution
        // because that's what we want to test here.
        String vendor = System.getProperty("java.vendor");
        this.vendorChecks = allPropertiesChecks.stream()
                .filter(checks -> checks.supports(vendor))
                .findFirst()
                .orElseThrow(() -> new AssertionError("No checks found for vendor: " + vendor));
    }

    /**
     * Verifies that the vendor name is displayed within
     * the java -version output, where applicable.
     */
    @Test
    public void javaVersionPrintsVendor() {
        String testJdkHome = System.getenv("TEST_JDK_HOME");
        if (testJdkHome == null) {
            throw new AssertionError("TEST_JDK_HOME is not set");
        }

        List<String> command = new ArrayList<>();
        command.add(String.format("%s/bin/java", testJdkHome));
        command.add("-version");

        try {
            ProcessBuilder processBuilder = new ProcessBuilder(command);
            Process process = processBuilder.start();

            String stderr = StreamUtils.consumeStream(process.getErrorStream());

            if (process.waitFor() != 0) {
                throw new AssertionError("Could not run java -version");
            }

            this.vendorChecks.javaVersion(stderr);
        } catch (InterruptedException | IOException e) {
            throw new RuntimeException("Failed to launch JVM", e);
        }
    }

    /**
     * Test method that calls a number of other test methods
     * themed around vendor-related property checks.
     */
    @Test
    public void vmPropertiesPointToVendor() {
        this.vendorChecks.javaVendor(System.getProperty("java.vendor"));
        this.vendorChecks.javaVendorUrl(System.getProperty("java.vendor.url"));
        this.vendorChecks.javaVendorUrlBug(System.getProperty("java.vendor.url.bug"));
        if (JDK_VERSION.isNewerOrEqual(10)) {
            this.vendorChecks.javaVendorVersion(System.getProperty("java.vendor.version"));
        }
        this.vendorChecks.javaVmVendor(System.getProperty("java.vm.vendor"));
        this.vendorChecks.javaVmVersion(System.getProperty("java.vm.version"));
    }

    private interface VmPropertiesChecks {
        /**
         * Tests whether the implementation of {@linkplain VmPropertiesChecks} is suitable to verify a JDK.
         * @param  vendor  Name identifying the vendor.
         * @return boolean result
         */
        boolean supports(String vendor);

        /**
         * Checks whether the output of {@code java -version} is acceptable.
         * @param value the value to be validated.
         */
        void javaVersion(String value);

        /**
         * Checks the value of {@code java.vendor}.
         * @param value the value to be validated.
         */
        void javaVendor(String value);

        /**
         * Checks the value of {@code java.vendor.url}.
         * @param value the value to be validated.
         */
        void javaVendorUrl(String value);

        /**
         * Checks the value of {@code java.vendor.url.bug}.
         * @param value the value to be validated.
         */
        void javaVendorUrlBug(String value);

        /**
         * Checks the value of {@code java.vendor.version}.
         * @param value the value to be validated.
         */
        void javaVendorVersion(String value);

        /**
         * Checks the value of {@code java.vm.vendor}.
         * @param value the value to be validated.
         */
        void javaVmVendor(String value);

        /**
         * Checks the value of {@code java.vm.version}.
         * @param value the value to be validated.
         */
        void javaVmVersion(String value);
    }

    private static class AdoptiumPropertiesChecks implements VmPropertiesChecks {

        @Override
        public boolean supports(final String vendor) {
            return vendor.toLowerCase(Locale.US).contains("adoptium");
        }

        @Override
        public void javaVersion(final String value) {
            if (JDK_VERSION.usesVM(VM.OPENJ9) && JDK_VERSION.isOlderThan(9)) {
                // For JDK8 on OpenJ9, the vendor name SHOULD NOT be present in the version output.
                assertFalse(value.contains("Temurin"));
            } else {
                // For all other JDKs, the vendor name SHOULD be present in the version output.
                assertTrue(value.contains("Temurin"));
            }
        }

        @Override
        public void javaVendor(final String value) {
            assertEquals(value, "Eclipse Adoptium");
        }

        @Override
        public void javaVendorUrl(final String value) {
            assertEquals(value, "https://adoptium.net/");
        }

        @Override
        public void javaVendorUrlBug(final String value) {
            assertEquals(value, "https://github.com/adoptium/adoptium-support/issues");
        }

        @Override
        public void javaVendorVersion(final String value) {
            assertNotEquals(value.replaceAll("[^0-9]", "").length(), 0,
                    "java.vendor.version contains no numbers: " + value);
        }

        @Override
        public void javaVmVendor(final String value) {
            assertTrue(value.equals("Eclipse Adoptium") || value.equals("Eclipse OpenJ9"));
        }

        @Override
        public void javaVmVersion(final String value) {
            assertNotEquals(value.replaceAll("[^0-9]", "").length(), 0,
                    "java.vm.version contains no numbers: " + value);
        }
    }

    private static class SemeruPropertiesChecks implements VmPropertiesChecks {

        @Override
        public boolean supports(final String vendor) {
            String vendorLowerCase = vendor.toLowerCase(Locale.US);
            return vendorLowerCase.contains("international business machines corporation") || vendorLowerCase.contains("ibm corporation");
        }

        @Override
        public void javaVersion(final String value) {
            assertTrue(value.toLowerCase().contains("openj9"));
        }

        @Override
        public void javaVendor(final String value) {
            if (value.toLowerCase(Locale.US).contains("ibm")) {
                assertEquals(value, "IBM Corporation");
            } else {
                assertEquals(value, "International Business Machines Corporation");
            }
        }

        @Override
        public void javaVendorUrl(final String value) {
            assertEquals(value, "https://www.ibm.com/semeru-runtimes");
        }

        @Override
        public void javaVendorUrlBug(final String value) {
            if (JDK_VERSION.isNewerOrEqual(11)) {
                assertEquals(value, "https://github.com/ibmruntimes/Semeru-Runtimes/issues");
            } else {
                assertEquals(value, null);
            }
        }

        @Override
        public void javaVendorVersion(final String value) {
            assertNotEquals(value.replaceAll("[^0-9]", "").length(), 0,
                    "java.vendor.version contains no numbers: " + value);
        }

        @Override
        public void javaVmVendor(final String value) {
            assertTrue(value.equals("Eclipse OpenJ9"));
        }

        @Override
        public void javaVmVersion(final String value) {
            assertNotEquals(value.replaceAll("[^0-9]", "").length(), 0,
                    "java.vm.version contains no numbers: " + value);
        }
    }

    private static class CorrettoPropertiesChecks implements VmPropertiesChecks {

        @Override
        public boolean supports(final String vendor) {
            return vendor.toLowerCase(Locale.US).startsWith("amazon");
        }

        @Override
        public void javaVersion(final String value) {
            assertTrue(value.contains("Corretto"));
        }

        @Override
        public void javaVendor(final String value) {
            assertEquals(value, "Amazon.com Inc.");
        }

        @Override
        public void javaVendorUrl(final String value) {
            assertEquals(value, "https://aws.amazon.com/corretto/");
        }

        @Override
        public void javaVendorUrlBug(final String value) {
            assertTrue(value.startsWith("https://github.com/corretto/corretto"));
        }

        @Override
        public void javaVendorVersion(final String value) {
            assertTrue(value.startsWith("Corretto"));
            assertNotEquals(value.replaceAll("[^0-9]", "").length(), 0,
                    "java.vendor.version contains no numbers: " + value);
        }

        @Override
        public void javaVmVendor(final String value) {
            assertEquals(value, "Amazon.com Inc.");
        }

        @Override
        public void javaVmVersion(final String value) {
            assertNotEquals(value.replaceAll("[^0-9]", "").length(), 0,
                    "java.vm.version contains no numbers: " + value);
        }
    }
}
