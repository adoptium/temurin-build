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

import java.util.Collection;
import java.util.Locale;

public final class JdkPlatform {

    private final Architecture architecture;

    private final OperatingSystem operatingSystem;

    /**
     * Constructor that detects the system architecture and os the test is running on.
     */
    public JdkPlatform() {
        this.architecture = detectArchitecture();
        this.operatingSystem = detectOperatingSystem();
    }

    /**
     * Checks if the given parameter <code>arch</code> can run on the system architecture that the test is running on.
     * @param arch The param architecture to check the system arch against
     * @return True if the param arch matches the system arch, false otherwise
     */
    public boolean runsOn(final Architecture arch) {
        return arch == this.architecture;
    }

    /**
     * Checks if the system architecture is in the collection of architectures given as a parameter.
     * @param architectures Collection of architectures
     * @return True if the system arch is in the collection, false otherwise
     */
    public boolean runsOnAnyArchitecture(final Collection<Architecture> architectures) {
        return architectures.contains(this.architecture);
    }

    /**
     * Checks if the given parameter <code>os</code> can run on the system operating system that the test is running on.
     * @param os The param operating system to check the system operating system against
     * @return True if the param os matches the system os, false otherwise
     */
    public boolean runsOn(final OperatingSystem os) {
        return os == this.operatingSystem;
    }

    /**
     * Checks if the given operating system and architecture (as parameters) match the system operating system and architecture.
     * @param os Operating System to check if the system architecture is the same one
     * @param arch Architecture to check if the system architecture is the same one
     * @return True if both the system arch and os match, false otherwise
     */
    public boolean runsOn(final OperatingSystem os, final Architecture arch) {
        return this.runsOn(os) && this.runsOn(arch);
    }

    /**
     * Checks if the system operating system is in the collection of operating systems given as a parameter.
     * @param operatingSystems Collection of operating systems
     * @return True if the system os is in the collection, false otherwise
     */
    public boolean runsOnAnyOperatingSystem(final Collection<OperatingSystem> operatingSystems) {
        return operatingSystems.contains(this.operatingSystem);
    }

    /**
     * Converts the system operating system and architecture string names to a custom string value.
     * @return Operating system and architecture names divided by a <code>/</code>
     */
    @Override
    public String toString() {
        return this.operatingSystem.name() + "/" + this.architecture.name();
    }

    /**
     * Will use the System Property <code>os.arch</code> to determine what system architecture it is running on.
     * @return Instance of the Architecture class that it is running on
     * @throws AssertionError If an unrecognised architecture is given
     */
    private static Architecture detectArchitecture() {
        String arch = normalize(System.getProperty("os.arch"));

        if (arch.matches("^(arm|arm32)$")) {
            return Architecture.ARM;
        }
        if (arch.equals("aarch64")) {
            return Architecture.AARCH64;
        }
        if (arch.equals("ppc64")) {
            return Architecture.PPC64;
        }
        if (arch.equals("ppc64le")) {
            return Architecture.PPC64LE;
        }
        if (arch.equals("riscv")) {
            return Architecture.RISCV;
        }
        if (arch.equals("riscv64")) {
            return Architecture.RISCV64;
        }
        if (arch.matches("^(sparc|sparc32)$")) {
            return Architecture.SPARC32;
        }
        if (arch.matches("^(sparcv9|sparc64)$")) {
            return Architecture.SPARC64;
        }
        if (arch.equals("s390x")) {
            return Architecture.S390X;
        }
        if (arch.matches("^(amd64|em64t|x64|x86_64)$")) {
            return Architecture.X64;
        }
        if (arch.matches("^(x86|i[3-6]86|ia32|x32)$")) {
            return Architecture.X86;
        }

        throw new AssertionError("Unrecognized architecture: " + arch);
    }

    /**
     * Will use the System Property <code>os.name</code> to determine what the system's operating system is.
     * @return Instance of the Operating System class that it is running on
     * @throws AssertionError If an unrecognised os is given
     */
    private static OperatingSystem detectOperatingSystem() {
        String osName = normalize(System.getProperty("os.name"));

        if (osName.contains("aix")) {
            return OperatingSystem.AIX;
        }
        if (osName.contains("bsd")) {
            return OperatingSystem.BSD;
        }
        if (osName.contains("linux")) {
            return OperatingSystem.LINUX;
        }
        if (osName.contains("mac")) {
            return OperatingSystem.MACOS;
        }
        if (osName.contains("solaris") || osName.contains("sunos")) {
            return OperatingSystem.SOLARIS;
        }
        if (osName.contains("win")) {
            return OperatingSystem.WINDOWS;
        }

        throw new AssertionError("Unrecognized operating system: " + osName);
    }

    /**
     * Trims and converts the given string to a lowercase value (or to an empty string if it is null).
     * @param str String to be converted
     * @return Lowercase representation of the given string with whitespaces and newlines removed
     */
    private static String normalize(final String str) {
        if (str == null) {
            return "";
        }
        return str.trim().toLowerCase(Locale.US);
    }

    enum Architecture {
        ARM, AARCH64, PPC64, PPC64LE, RISCV, RISCV64, SPARC32, SPARC64, S390X, X64, X86
    }

    enum OperatingSystem {
        AIX, BSD, LINUX, MACOS, SOLARIS, WINDOWS
    }
}
