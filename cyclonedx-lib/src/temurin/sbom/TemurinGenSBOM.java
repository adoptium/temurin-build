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
import org.cyclonedx.model.formulation.task.Command;
import org.cyclonedx.model.formulation.task.Step;
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

private static final class ParsedArgs {
    private final String cmd;
    private final String comment;
    private final String compName;
    private final String formulaName;
    private final String description;
    private final String fileName;
    private final String hash;
    private final String name;
    private final String tool;
    private final String type;
    private final String url;
    private final String value;
    private final String version;
    private final String workflowRef;
    private final String workflowName;
    private final String workflowStepName;
    private final String formulaPropName;
    private final String workflowUid;
    private final String executed;
    private final String rawTaskTypes;

    ParsedArgs(
        final String cmdParam,
        final String commentParam,
        final String compNameParam,
        final String formulaNameParam,
        final String descriptionParam,
        final String fileNameParam,
        final String hashParam,
        final String nameParam,
        final String toolParam,
        final String typeParam,
        final String urlParam,
        final String valueParam,
        final String versionParam,
        final String workflowRefParam,
        final String workflowNameParam,
        final String workflowStepNameParam,
        final String formulaPropNameParam,
        final String workflowUidParam,
        final String executedParam,
        final String rawTaskTypesParam
    ) {
        this.cmd = cmdParam;
        this.comment = commentParam;
        this.compName = compNameParam;
        this.formulaName = formulaNameParam;
        this.description = descriptionParam;
        this.fileName = fileNameParam;
        this.hash = hashParam;
        this.name = nameParam;
        this.tool = toolParam;
        this.type = typeParam;
        this.url = urlParam;
        this.value = valueParam;
        this.version = versionParam;
        this.workflowRef = workflowRefParam;
        this.workflowName = workflowNameParam;
        this.workflowStepName = workflowStepNameParam;
        this.formulaPropName = formulaPropNameParam;
        this.workflowUid = workflowUidParam;
        this.executed = executedParam;
        this.rawTaskTypes = rawTaskTypesParam;
        }
    }

        /**
        * Main entry.
        * @param args Arguments for sbom operation.
        */
        public static void main(final String[] args) {
            final ParsedArgs parsedArgs = parseArgs(args);
            try {
                final Bom bom = dispatch(parsedArgs, args);
                writeFile(bom, parsedArgs.fileName);
            } catch (Exception e) {
                echoArgs(args);
                System.out.println("\nException: " + e);
                System.exit(1);
            }
        }

        private static void echoArgs(final String[] raw) {
        for (int i = 0; i < raw.length; i++) {
            System.out.print(raw[i] + " ");
            }
        }

        private static ParsedArgs parseArgs(final String[] args) {
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
                final String a = args[i];
                if (a.equals("--jsonFile")) {
                    fileName = args[++i];
                    useJson = true;
                } else if (a.equals("--xmlFile")) {
                    fileName = args[++i];
                    useJson = false;
                } else if (a.equals("--version")) {
                    version = args[++i];
                } else if (a.equals("--name")) {
                    name = args[++i];
                } else if (a.equals("--value")) {
                    value = args[++i];
                } else if (a.equals("--url")) {
                    url = args[++i];
                } else if (a.equals("--comment")) {
                    comment = args[++i];
                } else if (a.equals("--hash")) {
                    hash = args[++i];
                } else if (a.equals("--compName")) {
                    compName = args[++i];
                } else if (a.equals("--formulaName")) {
                    formulaName = args[++i];
                } else if (a.equals("--description")) {
                    description = args[++i];
                } else if (a.equals("--type")) {
                    type = args[++i];
                } else if (a.equals("--tool")) {
                    tool = args[++i];
                } else if (a.equals("--createNewSBOM")) {
                    cmd = "createNewSBOM";
                } else if (a.equals("--addMetadata")) {
                    cmd = "addMetadata";
                } else if (a.equals("--addMetadataComponent")) {
                    cmd = "addMetadataComponent";
                } else if (a.equals("--addMetadataProp")) {
                    cmd = "addMetadataProperty";
                } else if (a.equals("--addComponent")) {
                    cmd = "addComponent";
                } else if (a.equals("--addComponentHash")) {
                    cmd = "addComponentHash";
                } else if (a.equals("--addComponentProp")) {
                    cmd = "addComponentProp";
                } else if (a.equals("--addMetadataTools")) {
                    cmd = "addMetadataTools";
                } else if (a.equals("--addFormulation")) {
                    cmd = "addFormulation";
                } else if (a.equals("--addFormulationComp")) {
                    cmd = "addFormulationComp";
                } else if (a.equals("--addFormulationCompProp")) {
                    cmd = "addFormulationCompProp";
                } else if (a.equals("--verbose")) {
                    verbose = true;
                } else if (a.equals("--addFormulaProp")) {
                    cmd = "addFormulaProp";
                } else if (a.equals("--formulaPropName")) {
                    formulaPropName = args[++i];
                } else if (a.equals("--addWorkflow")) {
                    cmd = "addWorkflow";
                } else if (a.equals("--workflowRef")) {
                    workflowRef = args[++i];
                } else if (a.equals("--workflowName")) {
                    workflowName = args[++i];
                } else if (a.equals("--workflowUid")) {
                    workflowUid = args[++i];
                } else if (a.equals("--taskTypes")) {
                    rawTaskTypes = args[++i];
                } else if (a.equals("--addWorkflowStep")) {
                    cmd = "addWorkflowStep";
                } else if (a.equals("--workflowStepName")) {
                    workflowStepName = args[++i];
                } else if (a.equals("--addWorkflowStepCmd")) {
                    cmd = "addWorkflowStepCmd";
                } else if (a.equals("--executed")) {
                    executed = args[++i];
                }
            }

            return new ParsedArgs(
                    cmd, comment, compName, formulaName, description, fileName, hash, name, tool, type, url,
                    value, version, workflowRef, workflowName, workflowStepName, formulaPropName, workflowUid,
                    executed, rawTaskTypes
            );
        }

        private static Bom dispatch(final ParsedArgs a, final String[] raw) throws Exception {
            switch (a.cmd) {
                case "createNewSBOM":           return execCreateNewSBOM();
                case "addMetadata":             return execAddMetadata(a);
                case "addMetadataComponent":    return execAddMetadataComponent(a);
                case "addMetadataProperty":     return execAddMetadataProperty(a);
                case "addFormulation":          return execAddFormulation(a);
                case "addFormulationComp":      return execAddFormulationComp(a);
                case "addFormulationCompProp":  return execAddFormulationCompProp(a);
                case "addMetadataTools":        return execAddMetadataTools(a);
                case "addComponent":            return execAddComponent(a);
                case "addComponentHash":        return execAddComponentHash(a);
                case "addComponentProp":        return execAddComponentProp(a);
                case "addFormulaProp":          return execAddFormulaProp(a);
                case "addWorkflow":             return execAddWorkflow(a);
                case "addWorkflowStep":         return execAddWorkflowStep(a);
                case "addWorkflowStepCmd":      return execAddWorkflowStepCmd(a);
                default:
                    echoArgs(raw);
                    System.out.println("\nPlease enter a valid command.");
                    System.exit(1);
                    return null;
            }
        }

        private static Bom execCreateNewSBOM() throws Exception {
            return createBom();
        }

        private static Bom execAddMetadata(final ParsedArgs a) throws Exception {
            return addMetadata(a.fileName);
        }

        private static Bom execAddMetadataComponent(final ParsedArgs a) throws Exception {
            return addMetadataComponent(a.fileName, a.name, a.type, a.version, a.description);
        }

        private static Bom execAddMetadataProperty(final ParsedArgs a) throws Exception {
            return addMetadataProperty(a.fileName, a.name, a.value);
        }

        private static Bom execAddFormulation(final ParsedArgs a) throws Exception {
            return addFormulation(a.fileName, a.formulaName);
        }

        private static Bom execAddFormulationComp(final ParsedArgs a) throws Exception {
            return addFormulationComp(a.fileName, a.formulaName, a.name, a.type);
        }

        private static Bom execAddFormulationCompProp(final ParsedArgs a) throws Exception {
            return addFormulationCompProp(a.fileName, a.formulaName, a.compName, a.name, a.value);
        }

        private static Bom execAddMetadataTools(final ParsedArgs a) throws Exception {
            return addMetadataTools(a.fileName, a.tool, a.version);
        }

        private static Bom execAddComponent(final ParsedArgs a) throws Exception {
            return addComponent(a.fileName, a.compName, a.version, a.description);
        }

        private static Bom execAddComponentHash(final ParsedArgs a) throws Exception {
            return addComponentHash(a.fileName, a.compName, a.hash);
        }

        private static Bom execAddComponentProp(final ParsedArgs a) throws Exception {
            return addComponentProperty(a.fileName, a.compName, a.name, a.value);
        }

        private static Bom execAddFormulaProp(final ParsedArgs a) throws Exception {
            return addFormulaProperty(a.fileName, a.formulaName, a.formulaPropName, a.value);
        }

        private static Bom execAddWorkflow(final ParsedArgs a) throws Exception {
            return addWorkflow(a.fileName, a.formulaName, a.workflowRef, a.workflowUid, a.workflowName, a.rawTaskTypes);
        }

        private static Bom execAddWorkflowStep(final ParsedArgs a) throws Exception {
            return addWorkflowStep(a.fileName, a.formulaName, a.workflowRef, a.workflowStepName, a.description);
        }

        private static Bom execAddWorkflowStepCmd(final ParsedArgs a) throws Exception {
            final String realWorkflowStepNameForCmd = a.workflowStepName != null ? a.workflowStepName : a.name;
            return addWorkflowStepCmd(a.fileName, a.formulaName, a.workflowRef, realWorkflowStepNameForCmd, a.executed);
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
            for (Step s : steps) {
                if (stepName.equals(s.getName())) {
                    return s;
                }
            }
        }
        return null;
    }

    static Bom addFormulaProperty(final String fileName, final String formulaRef, final String propName, final String propValue) {

        System.out.println("addFormlaProp is deactivated, property \"" + propName + "\" not created.");

        Bom bom = readFile(fileName);
        return bom;

        /*
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
        */
    }

    private static TaskType stringToTaskType(final String raw) {
        if (raw == null) {
            if (verbose) {
                System.out.println("No TaskType specified. Choosing \"other\". Specify TaskTypes using \"--taskTypes\"");
            }
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
            default:
            if (verbose) {
                System.out.println("\"" + trimmed + "\" is not a valid TaskType. Using \"other\" instead.");
            }
            return TaskType.OTHER;
        }
    }

    private static List<TaskType> parseTaskTypes(final String raw) {
        List<TaskType> out = new LinkedList<>();
        if (raw == null || raw.isEmpty()) {
            return out;
        }
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
