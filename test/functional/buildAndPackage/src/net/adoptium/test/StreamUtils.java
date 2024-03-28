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

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;

public final class StreamUtils {

    private StreamUtils() {
        // no instances
    }

    /**
     * Reads the entire {@link InputStream} into a string.
     *
     * @param inputStream Input stream to be converted into a string
     * @throws IOException If an I/O error occurs
     * @return String that has been read from the input stream
     */
    public static String consumeStream(final InputStream inputStream) throws IOException {
        String lineSeparator = System.getProperty("line.separator");
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(inputStream))) {
            StringBuilder builder = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                builder.append(line);
                builder.append(lineSeparator);
            }
            return builder.toString();
        }
    }
}
