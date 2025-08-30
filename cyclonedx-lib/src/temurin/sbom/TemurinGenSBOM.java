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

package temurin.sbom;

import org.cyclonedx.exception.GeneratorException;
import org.cyclonedx.generators.json.BomJsonGenerator;
import org.cyclonedx.generators.xml.BomXmlGenerator;
import org.cyclonedx.model.Bom;
import org.cyclonedx.model.Component;
import org.cyclonedx.model.formulation.Formula;
import org.cyclonedx.model.Hash;
import org.cyclonedx.model.Metadata;
import org.cyclonedx.model.metadata.ToolInformation;
import org.cyclonedx.model.OrganizationalContact;
import org.cyclonedx.model.OrganizationalEntity;
import org.cyclonedx.model.Property;
import org.cyclonedx.model.formulation.Workflow;
import org.cyclonedx.model.formulation.task.*; //Command, Step and Task
import org.cyclonedx.model.formulation.FormulationCommon.TaskType;
import org.cyclonedx.parsers.JsonParser;
import org.cyclonedx.parsers.XmlParser;
import org.cyclonedx.Version;
import java.io.FileReader;
import java.io.FileWriter;
import java.util.Collections;
import java.util.List;
import java.util.LinkedList;
import java.util.UUID;

/**
 * Command line tool to construct a CycloneDX SBOM.
 */
public final class TemurinGenSBOM {

    private static boolean verbose = false;
    private static boolean useJson = false;

    private TemurinGenSBOM() {
    }

    /**
     * Main entry.
     * @param args Arguments for sbom operation.
     */
    public static void main(final String[] args) {
        String cmd = "";
        String comment = null;
        String compName = null;
        String formulaName = null;
        String description = null;
        String fileName = null;
        String hash = null;
        String name = null;
        String tool = null;
        String type = null;
        String url = null;
        String value = null;
        String version = null;
        String workflowRef = null;
        String workflowName = null;
        String workflowStepName = null;
        String formulaPropName = null;
        String workflowUid = null;
        String executed = null;
        String rawTaskTypes = null;

        for (int i = 0; i < args.length; i++) {
            if (args[i].equals("--jsonFile")) {
                fileName = args[++i];
                useJson = true;
            } else if (args[i].equals("--xmlFile")) {
                fileName = args[++i];
                useJson = false;
            } else if (args[i].equals("--version")) {
                version = args[++i];
            } else if (args[i].equals("--name")) {
                name = args[++i];
            } else if (args[i].equals("--value")) {
                value = args[++i];
            } else if (args[i].equals("--url")) {
                url = args[++i];
            } else if (args[i].equals("--comment")) {
                comment = args[++i];
            } else if (args[i].equals("--hash")) {
                hash = args[++i];
            } else if (args[i].equals("--compName")) {
                compName = args[++i];
            } else if (args[i].equals("--formulaName")) {
                formulaName = args[++i];
            } else if (args[i].equals("--description")) {
                description = args[++i];
            } else if (args[i].equals("--type")) {
                type = args[++i];
            } else if (args[i].equals("--tool")) {
                tool =  args[++i];
            } else if (args[i].equals("--createNewSBOM")) {
                cmd = "createNewSBOM";
            } else if (args[i].equals("--addMetadata")) {               // Metadata Component. We can set "name" for Metadata.
                cmd = "addMetadata";
            } else if (args[i].equals("--addMetadataComponent")) {      // Metadata Component. We can set "name" for Metadata->Component.
                cmd = "addMetadataComponent";
            } else if (args[i].equals("--addMetadataProp")) {           // MetaData Component --> Property -> name-value
                cmd = "addMetadataProperty";
            } else if (args[i].equals("--addComponent")) {
                cmd = "addComponent";
            } else if (args[i].equals("--addComponentHash")) {
                cmd = "addComponentHash";
            } else if (args[i].equals("--addComponentProp")) {          // Components --> Property: will add name-value.
                cmd = "addComponentProp";
            } else if (args[i].equals("--addMetadataTools")) {
                cmd = "addMetadataTools";
            } else if (args[i].equals("--addFormulation")) {            // Formulation Component. We can set "name" for Formulation.
                cmd = "addFormulation";
            } else if (args[i].equals("--addFormulationComp")) {        // Formulation Component. We can set "name" for Formulation.
                cmd = "addFormulationComp";
            } else if (args[i].equals("--addFormulationCompProp")) {    // Formulation --> Component --> Property --> name-value
                cmd = "addFormulationCompProp";
            } else if (args[i].equals("--verbose")) {
                verbose = true;
            } else if (args[i].equals("--addFormulaProp")) {            // formulation --> properties
                cmd = "addFormulaProp";
            } else if (args[i].equals("--formulaPropName")) {           // formulation --> properties --> name
                formulaPropName = args[++i];
            } else if (args[i].equals("--addWorkflow")) {               // formulation --> workflows
                cmd = "addWorkflow";
            } else if (args[i].equals("--workflowRef")) {               // formulation --> workflows --> bom-ref
                workflowRef = args[++i];
            } else if (args[i].equals("--workflowName")) {              // formulation --> workflows --> name
                workflowName = args[++i];
            } else if (args[i].equals("--workflowUid")) {               // formulation --> workflows --> uid
                workflowUid = args[++i];
            } else if (args[i].equals("--taskTypes")) {                 // formulation --> workflows --> taskTypes
                rawTaskTypes = args[++i];
            } else if (args[i].equals("--addWorkflowStep")) {           // formulation --> workflows --> steps
                cmd = "addWorkflowStep";
            } else if (args[i].equals("--workflowStepName")) {          // formulation --> workflows --> steps --> name
                workflowStepName = args[++i];
            } else if (args[i].equals("--addWorkflowStepCmd")) {        // formulation --> workflows --> steps --> commands
                cmd = "addWorkflowStepCmd";
            } else if (args[i].equals("--executed")) {                  // formulation --> workflows --> steps --> commands --> executed
                executed = args[++i];
            }
        }
        try {
          switch (cmd) {
            case "createNewSBOM":                                    // Creates new SBOM
                Bom bom = createBom();
                writeFile(bom, fileName);
                break;

            case "addMetadata":                                      // Adds Metadata --> name
                bom = addMetadata(fileName);
                writeFile(bom, fileName);
                break;

            case "addMetadataComponent":                             // Adds Metadata --> Component --> name
                bom = addMetadataComponent(fileName, name, type, version, description);
                writeFile(bom, fileName);
                break;

            case "addMetadataProperty":                              // Adds MetaData --> Property --> name-value:
                bom = addMetadataProperty(fileName, name, value);
                writeFile(bom, fileName);
                break;

            case "addFormulation":                                   // Adds Formulation --> name
                bom = addFormulation(fileName, formulaName);
                writeFile(bom, fileName);
                break;

            case "addFormulationComp":                               // Adds Formulation --> Component--> name
                bom = addFormulationComp(fileName, formulaName, name, type);
                writeFile(bom, fileName);
                break;
            case "addFormulationCompProp":                           // Adds Formulation --> Component -> name-value:
                bom = addFormulationCompProp(fileName, formulaName, compName, name, value);
                writeFile(bom, fileName);
                break;

            case "addMetadataTools":
                bom = addMetadataTools(fileName, tool, version);
                writeFile(bom, fileName);
                break;

            case "addComponent":                                     // Adds Components --> Component --> name
                bom = addComponent(fileName, compName, version, description);
                writeFile(bom, fileName);
                break;

            case "addComponentHash":                                 // Adds Components --> Component --> hash
                bom = addComponentHash(fileName, compName, hash);
                writeFile(bom, fileName);
                break;

            case "addComponentProp":                                 // Adds Components --> Component --> name-value pairs
                bom = addComponentProperty(fileName, compName, name, value);
                writeFile(bom, fileName);
                break;

            case "addFormulaProp":
                String realFormulaPropName = formulaPropName != null ? formulaPropName : name;
                bom = addFormulaProperty(fileName, formulaName, realFormulaPropName, value);
                writeFile(bom, fileName);
                break;

            case "addWorkflow":
                String realWorkflowName = workflowName != null ? workflowName : name;
                bom = addWorkflow(fileName, formulaName, workflowRef, workflowUid, realWorkflowName, rawTaskTypes);
                writeFile(bom, fileName);
                break;

            case "addWorkflowStep":
                String realWorkflowStepName = workflowStepName != null ? workflowStepName : name;
                bom = addWorkflowStep(fileName, formulaName, workflowRef, realWorkflowStepName, description);
                writeFile(bom, fileName);
                break;

            case "addWorkflowStepCmd":
                String realWorkflowStepNameForCmd = workflowStepName != null ? workflowStepName : name;
                bom = addWorkflowStepCmd(fileName, formulaName, workflowRef, realWorkflowStepNameForCmd, executed);
                writeFile(bom, fileName);
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

    /*
     * Create SBOM file in json format with default "bomFormat" "specVersion" and "version"
     * Add default compo
     */
    static Bom createBom() {
        Bom bom = new Bom();
        bom.setSerialNumber("urn:uuid:" + UUID.randomUUID());
        return bom;
    }

    // Create Metadata if it doesn't exist
    static Metadata getBomMetadata(final Bom bom) {
        Metadata metadata = bom.getMetadata();
        if (metadata == null) {
            metadata = new Metadata();
        }
        return metadata;
    }

    // Method to store Metadata --> name.
    static Bom addMetadata(final String fileName) {
        Bom bom = readFile(fileName);
        Metadata meta = getBomMetadata(bom);
        OrganizationalEntity org = new OrganizationalEntity();
        org.setName("Eclipse Foundation");
        org.setUrls(Collections.singletonList("https://www.eclipse.org/"));
        meta.setManufacture(org);
        OrganizationalContact auth = new OrganizationalContact();
        auth.setName("Adoptium Temurin");
        meta.addAuthor(auth);
        bom.setMetadata(meta);
        return bom;
    }

    static Bom addMetadataComponent(final String fileName, final String name, final String type, final String version, final String description) {
        Bom bom = readFile(fileName);
        Metadata meta = getBomMetadata(bom);
        Component comp = new Component();
        Component.Type compType = Component.Type.FRAMEWORK;
        switch (type) {
            case "os":
                compType = Component.Type.OPERATING_SYSTEM;
                break;
            default:
                break;
        }
        comp.setType(compType); // required e.g Component.Type.FRAMEWORK
        comp.setName(name); // required
        comp.setVersion(version);
        comp.setDescription(description);
        meta.setComponent(comp);
        bom.setMetadata(meta);
        return bom;
    }

    // Method to store Metadata --> Properties List --> name-values.
    static Bom addMetadataProperty(final String fileName, final String name, final String value) {
        Bom bom = readFile(fileName);
        Metadata meta = getBomMetadata(bom);
        Property prop1 = new Property();
        prop1.setName(name);
        prop1.setValue(value);
        meta.addProperty(prop1);
        bom.setMetadata(meta);
        return bom;
    }

    static Bom addMetadataTools(final String fileName, final String toolName, final String version) {
        Bom bom = readFile(fileName);
        Metadata meta = getBomMetadata(bom);

        // Create Tool Component
        Component tool = new Component();
        tool.setType(Component.Type.APPLICATION);
        tool.setName(toolName);
        tool.setVersion(version);

        // Create ToolInformation if not already
        ToolInformation tools = meta.getToolChoice();
        if (tools == null) {
            tools = new ToolInformation();
        }

        // Create new components array, add existing to it
        List<Component> components = tools.getComponents();
        if (components == null) {
            components = new LinkedList<Component>();
        }

        components.add(tool);
        tools.setComponents(components);
        meta.setToolChoice(tools);

        bom.setMetadata(meta);
        return bom;
    }

    // Method to store Component --> name & single name-value pair.
    static Bom addComponent(final String fileName, final String compName, final String version, final String description) {
        Bom bom = readFile(fileName);
        Component comp = new Component();
        comp.setName(compName);
        comp.setVersion(version);
        comp.setType(Component.Type.FRAMEWORK);
        comp.setDescription(description);
        comp.setGroup("adoptium.net");
        comp.setAuthor("Eclipse Temurin");
        comp.setPublisher("Eclipse Temurin");
        bom.addComponent(comp);
        return bom;
    }

    static Bom addComponentHash(final String fileName, final String compName, final String hash) {
        Bom bom = readFile(fileName);
        List<Component> componentArrayList = bom.getComponents();
        for (Component item : componentArrayList) {
            if (item.getName().equals(compName)) {
                    Hash hash1 = new Hash(Hash.Algorithm.SHA_256, hash);
                    item.addHash(hash1);
            }
        }
        return bom;
    }

    // Method to add Component --> Property --> name-value pairs.
    static Bom addComponentProperty(final String fileName, final String compName, final String name, final String value) {
        Bom bom = readFile(fileName);
        List<Component> componentArrayList = bom.getComponents();
        for (Component item : componentArrayList) {
            if (item.getName().equals(compName)) {
                    Property prop1 = new Property();
                    prop1.setName(name);
                    prop1.setValue(value);
                    item.addProperty(prop1);
            }
        }
        return bom;
    }

    static Bom addFormulation(final String fileName, final String name) {
        Bom bom = readFile(fileName);
        List<Formula> formulation = bom.getFormulation();
        if (formulation == null) {
            formulation = new LinkedList<Formula>();
            bom.setFormulation(formulation);
        }
        Formula formula = new Formula();
        formula.setBomRef(name);
        formulation.add(formula);

        return bom;
    }

   static Bom addFormulationComp(final String fileName, final String formulaName, final String name, final String type) {
        Bom bom = readFile(fileName);
        if (formulaName == null) {
           System.out.println("addFormulationComp: formulaName is null");
           return bom;
        } else if (name == null) {
           System.out.println("addFormulationComp: name is null");
           return bom;
        }
        List<Formula> formulation = bom.getFormulation();
        // Look for the formula, and add the new component to it
        boolean found = false;
        for (Formula item : formulation) {
          if (item.getBomRef().equals(formulaName)) {
            found = true;
            Component comp = new Component();
            Component.Type compType = Component.Type.FRAMEWORK;
            comp.setType(Component.Type.FRAMEWORK);
            comp.setName(name);
            List<Component> components = item.getComponents();
            if (components == null) {
              components = new LinkedList<Component>();
            }
            components.add(comp);
            item.setComponents(components);
          }
        }
        if (!found) {
          System.out.println("addFormulationComp could not add component as it couldn't find an entry for formula " + formulaName);
        }
        return bom;
    }

    static Bom addFormulationCompProp(final String fileName, final String formulaName, final String componentName, final String name, final String value) {
        Bom bom = readFile(fileName);
        boolean foundFormula = false;
        boolean foundComponent = false;
        List<Formula> formulation = bom.getFormulation();
        // Look for the formula, and add the new component to it
        for (Formula item : formulation) {
          if (item.getBomRef().equals(formulaName)) {
            foundFormula = true;
            // Search for the component in the formula and add new component to it
            List<Component> components = item.getComponents();
            if (components == null) {
              System.out.println("addFormulationCompProp: Components is null - has addFormulationComp been called?");
            } else {
              for (Component comp : components) {
                if (comp.getName().equals(componentName)) {
                  foundComponent = true;
                  Property prop1 = new Property();
                  prop1.setName(name);
                  prop1.setValue(value);
                  comp.addProperty(prop1);
                  item.setComponents(components);
                }
              }
            }
          }
        }
        if (!foundFormula) {
          System.out.println("addFormulationCompProp could not add add property as it couldn't find an entry for formula " + formulaName);
        } else if (!foundComponent) {
          System.out.println("addFormulationCompProp could not add add property as it couldn't find an entry for component " + componentName);
        }
        return bom;
    }

    private static Formula getOrCreateFormula(final Bom bom, final String formulaRef) {
        List<Formula> formulas = bom.getFormulation();
        if (formulas == null) {
            formulas = new LinkedList<>();
            bom.setFormulation(formulas);
        }
        for (Formula f : formulas) {
            if (formulaRef != null && formulaRef.equals(f.getBomRef())) {
                return f;
            }
        }
        Formula f = new Formula();
        f.setBomRef(formulaRef);
        formulas.add(f);
        return f;
    }

    private static Workflow getOrCreateWorkflow(final Formula f, final String workflowRef) {
        List<Workflow> wfs = f.getWorkflows();
        if (wfs == null) {
            wfs = new LinkedList<>();
            f.setWorkflows(wfs);
        }
        for (Workflow w : wfs) {
            if (workflowRef != null && workflowRef.equals(w.getBomRef())) {
                return w;
            }
        }
        Workflow w = new Workflow();
        w.setBomRef(workflowRef);
        wfs.add(w);
        return w;
    }

    private static Step findStepByName(final Workflow wf, final String stepName) {
        List<Step> steps = wf.getSteps();
        if (steps == null) {
            return null;
        }
        if (stepName != null) {
            for (Step s : steps) if (stepName.equals(s.getName())) return s;
        }
        return null;
    }

    static Bom addFormulaProperty(final String fileName, final String formulaRef, final String propName, final String propValue) {
        Bom bom = readFile(fileName);
        Formula f = getOrCreateFormula(bom, formulaRef);

        Property p = new Property();
        p.setName(propName);
        p.setValue(propValue);

        List<Property> props = f.getProperties();
        if (props == null)  {
            props = new LinkedList<>();
        }
        props.add(p);
        f.setProperties(props);

        return bom;
    }

    private static TaskType stringToTaskType(final String raw) {
        if (raw == null) {
            System.out.println("No TaskType specified. Choosing \"other\". Specify TaskTypes using \"--taskTypes\"");
            return TaskType.OTHER;
        }
        String trimmed = raw.trim().toLowerCase();
        switch (trimmed) {
            case "build": return TaskType.BUILD;
            case "clean": return TaskType.CLEAN;
            case "clone": return TaskType.CLONE;
            case "copy": return TaskType.COPY;
            case "deliver": return TaskType.DELIVER;
            case "deploy": return TaskType.DEPLOY;
            case "lint": return TaskType.LINT;
            case "merge": return TaskType.MERGE;
            case "other": return TaskType.OTHER;
            case "release": return TaskType.RELEASE;
            case "scan": return TaskType.SCAN;
            case "test": return TaskType.TEST;
        }
        System.out.println(trimmed + " is not a valid TaskType. Picking \"other\" instead.");
        return TaskType.OTHER;
    }

    private static List<TaskType> parseTaskTypes(final String raw) {
        List<TaskType> out = new LinkedList<>();
        if (raw == null || raw.isEmpty()) {
            return out;}
        for (String s : raw.split(",")) {
            String t = s.trim();
            if (!t.isEmpty()) {
                out.add(stringToTaskType(t));
            }
        }
        return out;
    }

    static Bom addWorkflow(final String fileName, final String formulaRef, final String workflowRef, final String uid, final String wfName, final String rawTaskTypes) {
        Bom bom = readFile(fileName);
        Formula f = getOrCreateFormula(bom, formulaRef);
        Workflow wf = getOrCreateWorkflow(f, workflowRef);

        if (uid != null) {
            wf.setUid(uid);
        }
        if (wfName != null) {
            wf.setName(wfName);
        }

        List<TaskType> types = parseTaskTypes(rawTaskTypes);
        if (types != null && !types.isEmpty()) {
            wf.setTaskTypes(types);
        }
        return bom;
    }

    static Bom addWorkflowStep(final String fileName, final String formulaRef, final String workflowRef, final String stepName, final String stepDesc) {
        Bom bom = readFile(fileName);
        Formula f = getOrCreateFormula(bom, formulaRef);
        Workflow wf = getOrCreateWorkflow(f, workflowRef);

        List<Step> steps = wf.getSteps();
        if (steps == null) {
            steps = new LinkedList<>();
        }

        Step s = findStepByName(wf, stepName);
        if (s == null) {
            s = new Step();
            s.setName(stepName);
            s.setDescription(stepDesc);
            steps.add(s);
        }
        wf.setSteps(steps);
        return bom;
    }

    static Bom addWorkflowStepCmd(final String fileName, final String formulaRef, final String workflowRef, final String stepName, final String cmdExecuted) {
        Bom bom = readFile(fileName);
        Formula f = getOrCreateFormula(bom, formulaRef);
        Workflow wf = getOrCreateWorkflow(f, workflowRef);

        Step target = findStepByName(wf, stepName);
        if (target == null) {
            throw new IllegalArgumentException("Step not found. (name): " + stepName);
        }

        List<Command> cmds = target.getCommands();
        if (cmds == null) {
            cmds = new LinkedList<>();
        }
        Command c = new Command();
        c.setExecuted(cmdExecuted);
        cmds.add(c);
        target.setCommands(cmds);

        return bom;
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

    // Read the BOM object from the specified type of file
    static Bom readFile(final String fileName) {
        Bom bom;
        if (useJson) {
            bom = readJSONfile(fileName);
        } else {
            bom = readXMLfile(fileName);
        }
        return bom;
    }

    // Writes the BOM object to the specified file.
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
