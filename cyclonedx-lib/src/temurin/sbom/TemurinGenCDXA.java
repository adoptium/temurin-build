/*
 * ********************************************************************************
 * Copyright (c) 2024 Contributors to the Eclipse Foundation
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

package temurin.sbom;

import org.cyclonedx.exception.GeneratorException;
import org.cyclonedx.generators.json.BomJsonGenerator;
import org.cyclonedx.generators.xml.BomXmlGenerator;
import org.cyclonedx.model.Bom;
import org.cyclonedx.model.Component;
import org.cyclonedx.model.ExternalReference;
import org.cyclonedx.model.Hash;
import org.cyclonedx.model.OrganizationalEntity;
import org.cyclonedx.model.attestation.Declarations;
import org.cyclonedx.model.attestation.Assessor;
import org.cyclonedx.model.attestation.Attestation;
import org.cyclonedx.model.attestation.AttestationMap;
import org.cyclonedx.model.attestation.Claim;
import org.cyclonedx.model.attestation.affirmation.Affirmation;
import org.cyclonedx.model.attestation.affirmation.Signatory;
import org.cyclonedx.model.attestation.Targets;
import org.cyclonedx.parsers.JsonParser;
import org.cyclonedx.parsers.XmlParser;
import org.cyclonedx.Version;
import java.io.FileReader;
import java.io.FileWriter;
import java.util.List;
import java.util.LinkedList;
import java.util.UUID;

/**
 * Command line tool to construct a CycloneDX CDXA.
 */
public final class TemurinGenCDXA {

    private static boolean verbose = false;
    private static boolean useJson = false;

    // Valid predicates
    enum CDXAPredicate {
                           VERIFIED_REPRODUCIBLE_BUILD
                       };

    private TemurinGenCDXA() {
    }

    /**
     * Main entry.
     * @param args Arguments for operation.
     */
    public static void main(final String[] args) {
        String cmd = "";
        String fileName = null;
        String attestingOrgName = null;
        String predicate = null;
        String targetName = null;
        String targetUrl = null;
        String targetHash = null;
        String affirmationStmt = null;
        String affirmationWebsite = null;
        boolean thirdParty = true;

        for (int i = 0; i < args.length; i++) {
            if (args[i].equals("--jsonFile")) {
                fileName = args[++i];
                useJson = true;
            } else if (args[i].equals("--xmlFile")) {
                fileName = args[++i];
                useJson = false;
            } else if (args[i].equals("--attesting-org-name")) {
                attestingOrgName = args[++i];
            } else if (args[i].equals("--predicate")) {
                predicate = args[++i];
            } else if (args[i].equals("--target-name")) {
                targetName = args[++i];
            } else if (args[i].equals("--target-url")) {
                targetUrl = args[++i];
            } else if (args[i].equals("--target-sha256-hash")) {
                targetHash = args[++i];
            } else if (args[i].equals("--affirmation-stmt")) {
                affirmationStmt = args[++i];
            } else if (args[i].equals("--affirmation-website")) {
                affirmationWebsite = args[++i];
            } else if (args[i].equals("--not-third-party")) {
                thirdParty = false;
            } else if (args[i].equals("--createNewCDXA")) {
                cmd = "createCDXA";
            } else if (args[i].equals("--verbose")) {
                verbose = true;
            }
        }

        try {
          switch (cmd) {
            case "createCDXA":  // Create a new CDXA json file
                Bom bom = createCdxa(fileName, attestingOrgName, predicate, targetName, targetUrl, targetHash, affirmationStmt, affirmationWebsite, thirdParty);
                if (bom != null) {
                    writeFile(bom, fileName);
                } else {
                    System.exit(1);
                }
                break;

            default:
                // Echo input command:
                for (int i = 0; i < args.length; i++) {
                    System.out.print(args[i] + " ");
                }
                System.out.println("\nPlease enter a valid command.");
                System.exit(1);
          }
        } catch (Exception e) {
            // Echo input command:
            for (int i = 0; i < args.length; i++) {
                System.out.print(args[i] + " ");
            }
            System.out.println("\nException: " + e);
            System.exit(1);
        }
    }

    static Bom createCdxa(final String fileName, final String attestingOrgName, final String predicate,
                          final String targetName, final String targetUrl, final String targetHash,
                          final String affirmationStmt, final String affirmationWebsite, final boolean thirdParty) {
        // Validate inputs
        boolean validInput = true;
        if (fileName == null) {
            System.out.println("--xmlFile|--jsonFile not specified");
            validInput = false;
         }
        if (attestingOrgName == null) {
            System.out.println("--attesting-org-name not specified");
            validInput = false;
        }
        if (predicate == null) {
            System.out.println("--predicate not specified"); validInput = false;
        } else {
            boolean validPred = false;
            for (CDXAPredicate validPredicate : CDXAPredicate.values()) {
                if (validPredicate.name().equals(predicate)) {
                    validPred = true;
                    break;
                }
            }
            if (!validPred) {
                System.out.println("--predicate " + predicate + " not a valid value");
                validInput = false;
            }
        }
        if (targetName == null) {
            System.out.println("--target-name not specified");
            validInput = false;
        }
        if (targetUrl == null) {
            System.out.println("--target-url not specified");
            validInput = false;
        }
        if (targetHash == null) {
            System.out.println("--target-sha256-hash not specified");
            validInput = false;
        }
        if (affirmationStmt == null) {
            System.out.println("--affirmation-stmt not specified");
            validInput = false;
        }
        if (affirmationWebsite == null) {
            System.out.println("--affirmation-website not specified");
            validInput = false;
        }
        if (!validInput) {
            return null;
        }

        Declarations   declarations = new Declarations();
        Assessor       assessor     = new Assessor();
        Claim          claim        = new Claim();
        Targets        targets      = new Targets();
        Affirmation    affirmation  = new Affirmation();
        Signatory      signatory    = new Signatory();
        Attestation    attestation  = new Attestation();
        AttestationMap attestationMap = new AttestationMap();

        final String targetJdkBomRef  = "target-jdk-1";
        final String assessorBomRef   = "assessor-1";
        final String claimBomRef      = "claim-1";

        // External reference to the target JDK
        ExternalReference extRef = new ExternalReference();
        Hash hash1 = new Hash(Hash.Algorithm.SHA_256, targetHash);
        extRef.addHash(hash1);
        extRef.setUrl(targetUrl);
        extRef.setType(ExternalReference.Type.DISTRIBUTION);

        // Target JDK Component
        Component targetJDK = new Component();
        targetJDK.setType(Component.Type.APPLICATION);
        targetJDK.setName(targetName);
        targetJDK.addExternalReference(extRef);
        targetJDK.setBomRef(targetJdkBomRef);
        List<Component> components = new LinkedList<Component>();
        components.add(targetJDK);
        targets.setComponents(components);
        declarations.setTargets(targets);

        // Assessor
        assessor.setThirdParty(thirdParty);
        OrganizationalEntity org = new OrganizationalEntity();
        org.setName(attestingOrgName);
        assessor.setOrganization(org);
        assessor.setBomRef(assessorBomRef);
        List<Assessor> assessors = new LinkedList<Assessor>();
        assessors.add(assessor);
        declarations.setAssessors(assessors);

        // Claim
        claim.setPredicate(predicate);
        claim.setTarget(targetJDK.getBomRef());
        claim.setBomRef(claimBomRef);
        List<Claim> claims = new LinkedList<Claim>();
        claims.add(claim);
        declarations.setClaims(claims);

        // Affirmation
        affirmation.setStatement(affirmationStmt);
        signatory.setOrganization(org);
        ExternalReference orgExtRef = new ExternalReference();
        orgExtRef.setUrl(affirmationWebsite);
        orgExtRef.setType(ExternalReference.Type.WEBSITE);
        signatory.setExternalReference(orgExtRef);
        List<Signatory> signatories = new LinkedList<Signatory>();
        signatories.add(signatory);
        affirmation.setSignatories(signatories);
        declarations.setAffirmation(affirmation);

        // Construct the Attestation
        attestation.setSummary("Eclipse Temurin Attestation");
        attestation.setAssessor(assessor.getBomRef());
        List<String> claimsList = new LinkedList<String>();
        claimsList.add(claim.getBomRef());
        attestationMap.setClaims(claimsList);
        List<AttestationMap> attestationMaps = new LinkedList<AttestationMap>();
        attestationMaps.add(attestationMap);
        attestation.setMap(attestationMaps);
        List<Attestation> attestations = new LinkedList<Attestation>();
        attestations.add(attestation);
        declarations.setAttestations(attestations);

        // Create CDXA Bom
        Bom cdxa = new Bom();
        cdxa.setSerialNumber("urn:uuid:" + UUID.randomUUID());
        cdxa.setDeclarations(declarations);

        return cdxa;
    }

    static String generateBomJson(final Bom bom) throws GeneratorException {
        // Use schema v16: https://cyclonedx.org/schema/bom-1.6.schema.json
        BomJsonGenerator bomGen = new BomJsonGenerator(bom, Version.VERSION_16);
        String json = bomGen.toJsonString();
        return json;
    }

    static String generateBomXml(final Bom bom) throws GeneratorException {
        BomXmlGenerator bomGen = new BomXmlGenerator(bom, Version.VERSION_16);
        String xml = bomGen.toXmlString();
        return xml;
    }

    // Writes the BOM object to the specified type of file
    static void writeFile(final Bom bom, final String fileName) {
        if (useJson) {
            writeJSONfile(bom, fileName);
        } else {
            writeXMLfile(bom, fileName);
        }
    }

    // Writes the BOM object to the specified JSON file.
    static void writeJSONfile(final Bom bom, final String fileName) {
        FileWriter file;
        try {
            String json = generateBomJson(bom);

            file = new FileWriter(fileName);
            file.write(json);
            file.close();
        } catch (Exception e) {
            e.printStackTrace();
            System.exit(1);
        }
    }

    // Writes the BOM object to the specified XML file.
    static void writeXMLfile(final Bom bom, final String fileName) {
        FileWriter file;
        try {
            String xml = generateBomXml(bom);

            file = new FileWriter(fileName);
            file.write(xml);
            file.close();
        } catch (Exception e) {
            e.printStackTrace();
            System.exit(1);
        }
    }

    // Returns a parsed BOM object from the specified file.
    static Bom readJSONfile(final String fileName) {
        Bom bom = null;
        try {
            FileReader reader = new FileReader(fileName);
            JsonParser parser = new JsonParser();
            bom = parser.parse(reader);
        } catch (Exception e) {
            e.printStackTrace();
            System.exit(1);
        } finally {
           return bom;
        }
    }

    // Returns a parsed BOM object from the specified file.
    static Bom readXMLfile(final String fileName) {
        Bom bom = null;
        try {
            FileReader reader = new FileReader(fileName);
            XmlParser parser = new XmlParser();
            bom = parser.parse(reader);
        } catch (Exception e) {
            e.printStackTrace();
            System.exit(1);
        } finally {
           return bom;
        }
    }
}
