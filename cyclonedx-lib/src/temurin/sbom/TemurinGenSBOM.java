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
        private String cmd = "";
        private String comment;
        private String compName;
        private String description;
        private String executed;
        private String formulaName;
        private String formulaPropName;
        private String fileName;
        private String hash;
        private String name;
        private String rawTaskTypes;
        private String tool;
        private String type;
        private String url;
        private String value;
        private String version;
        private String workflowRef;
        private String workflowName;
        private String workflowStepName;
        private String workflowUid;
        private boolean verbose;
        private boolean useJson;

        //Getters and Setters
        public String getCmd() {
            return cmd;
        }
        public void setCmd(final String cmdParam) {
            this.cmd = cmdParam;
        }

        public String getFileName() {
            return fileName;
        }
        public void setFileName(final String fileNameParam) {
            this.fileName = fileNameParam;
        }

        public boolean isUseJson() {
            return useJson;
        }
        public void setUseJson(final boolean useJsonFlag) {
            this.useJson = useJsonFlag;
        }

        public boolean isVerbose() {
            return verbose;
        }
        public void setVerbose(final boolean verboseFlag) {
            this.verbose = verboseFlag;
        }

        public String getWorkflowRef() {
            return workflowRef;
        }
        public void setWorkflowRef(final String workflowRefParam) {
            this.workflowRef = workflowRefParam;
        }

        public String getWorkflowName() {
            return workflowName;
        }
        public void setWorkflowName(final String workflowNameParam) {
            this.workflowName = workflowNameParam;
        }

        public String getWorkflowStepName() {
            return workflowStepName;
        }
        public void setWorkflowStepName(final String workflowStepNameParam) {
            this.workflowStepName = workflowStepNameParam;
        }

        public String getWorkflowUid() {
            return workflowUid;
        }
        public void setWorkflowUid(final String workflowUidParam) {
            this.workflowUid = workflowUidParam;
        }

        public String getRawTaskTypes() {
            return rawTaskTypes;
        }
        public void setRawTaskTypes(final String rawTaskTypesParam) {
            this.rawTaskTypes = rawTaskTypesParam;
        }

        public String getFormulaName() {
            return formulaName;
        }
        public void setFormulaName(final String formulaNameParam) {
            this.formulaName = formulaNameParam;
        }

        public String getName() {
            return name;
        }
        public void setName(final String nameParam) {
            this.name = nameParam;
        }

        public String getDescription() {
            return description;
        }
        public void setDescription(final String descriptionParam) {
            this.description = descriptionParam;
        }

        public String getExecuted() {
            return executed;
        }
        public void setExecuted(final String executedParam) {
            this.executed = executedParam;
        }

        public String getType() {
            return type;
        }
        public void setType(final String typeParam) {
            this.type = typeParam;
        }

        public String getTool() {
            return tool;
        }
        public void setTool(final String toolParam) {
            this.tool = toolParam;
        }

        public String getCompName() {
            return compName;
        }
        public void setCompName(final String compNameParam) {
            this.compName = compNameParam;
        }

        public String getVersion() {
            return version;
        }
        public void setVersion(final String versionParam) {
            this.version = versionParam;
        }

        public String getHash() {
            return hash;
        }
        public void setHash(final String hashParam) {
            this.hash = hashParam;
        }

        public String getValue() {
            return value;
        }
        public void setValue(final String valueParam) {
            this.value = valueParam;
        }

        public String getUrl() {
            return url;
        }
        public void setUrl(final String urlParam) {
            this.url = urlParam;
        }

        public String getComment() {
            return comment;
        }
        public void setComment(final String commentParam) {
            this.comment = commentParam;
        }

        public String getFormulaPropName() {
            return formulaPropName;
        }
        public void setFormulaPropName(final String formulaPropNameParam) {
            this.formulaPropName = formulaPropNameParam;
        }
    }

        /**
        * Main entry.
        * @param args Arguments for sbom operation.
        */
        public static void main(final String[] args) {
            final ParsedArgs parsedArgs = parseArgs(args);

            //Mirror into the class variables
            useJson = parsedArgs.isUseJson();
            verbose = parsedArgs.isVerbose();

            try {
                final Bom bom = dispatch(parsedArgs, args);
                writeFile(bom, parsedArgs.getFileName());
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

            final ParsedArgs pa = new ParsedArgs();

            for (int i = 0; i < args.length; i++) {
                final String a = args[i];
                if (a.equals("--jsonFile")) {
                    pa.setFileName(args[++i]);
                    pa.setUseJson(true);
                } else if (a.equals("--xmlFile")) {
                    pa.setFileName(args[++i]);
                    pa.setUseJson(false);
                } else if (a.equals("--version")) {
                    pa.setVersion(args[++i]);
                } else if (a.equals("--name")) {
                    pa.setName(args[++i]);
                } else if (a.equals("--value")) {
                    pa.setValue(args[++i]);
                } else if (a.equals("--url")) {
                    pa.setUrl(args[++i]);
                } else if (a.equals("--comment")) {
                    pa.setComment(args[++i]);
                } else if (a.equals("--hash")) {
                    pa.setHash(args[++i]);
                } else if (a.equals("--compName")) {
                    pa.setCompName(args[++i]);
                } else if (a.equals("--formulaName")) {
                    pa.setFormulaName(args[++i]);
                } else if (a.equals("--description")) {
                    pa.setDescription(args[++i]);
                } else if (a.equals("--type")) {
                    pa.setType(args[++i]);
                } else if (a.equals("--tool")) {
                    pa.setTool(args[++i]);
                } else if (a.equals("--createNewSBOM")) {
                    pa.setCmd("createNewSBOM");
                } else if (a.equals("--addMetadata")) {
                    pa.setCmd("addMetadata");
                } else if (a.equals("--addMetadataComponent")) {
                    pa.setCmd("addMetadataComponent");
                } else if (a.equals("--addMetadataProp")) {
                    pa.setCmd("addMetadataProperty");
                } else if (a.equals("--addComponent")) {
                    pa.setCmd("addComponent");
                } else if (a.equals("--addComponentHash")) {
                    pa.setCmd("addComponentHash");
                } else if (a.equals("--addComponentProp")) {
                    pa.setCmd("addComponentProp");
                } else if (a.equals("--addMetadataTools")) {
                    pa.setCmd("addMetadataTools");
                } else if (a.equals("--addFormulation")) {
                    pa.setCmd("addFormulation");
                } else if (a.equals("--addFormulationComp")) {
                    pa.setCmd("addFormulationComp");
                } else if (a.equals("--addFormulationCompProp")) {
                    pa.setCmd("addFormulationCompProp");
                } else if (a.equals("--verbose")) {
                    pa.setVerbose(true);
                } else if (a.equals("--addFormulaProp")) {
                    pa.setCmd("addFormulaProp");
                } else if (a.equals("--formulaPropName")) {
                    pa.setFormulaPropName(args[++i]);
                } else if (a.equals("--addWorkflow")) {
                    pa.setCmd("addWorkflow");
                } else if (a.equals("--workflowRef")) {
                    pa.setWorkflowRef(args[++i]);
                } else if (a.equals("--workflowName")) {
                    pa.setWorkflowName(args[++i]);
                } else if (a.equals("--workflowUid")) {
                    pa.setWorkflowUid(args[++i]);
                } else if (a.equals("--taskTypes")) {
                    pa.setRawTaskTypes(args[++i]);
                } else if (a.equals("--addWorkflowStep")) {
                    pa.setCmd("addWorkflowStep");
                } else if (a.equals("--workflowStepName")) {
                    pa.setWorkflowStepName(args[++i]);
                } else if (a.equals("--addWorkflowStepCmd")) {
                    pa.setCmd("addWorkflowStepCmd");
                } else if (a.equals("--executed")) {
                    pa.setExecuted(args[++i]);
                }
            }
            return pa;
        }

        private static Bom dispatch(final ParsedArgs a, final String[] raw) throws Exception {
            switch (a.getCmd()) {
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
            return addMetadata(a.getFileName());
        }

        private static Bom execAddMetadataComponent(final ParsedArgs a) throws Exception {
            return addMetadataComponent(a.getFileName(), a.getName(), a.getType(), a.getVersion(), a.getDescription());
        }

        private static Bom execAddMetadataProperty(final ParsedArgs a) throws Exception {
            return addMetadataProperty(a.getFileName(), a.getName(), a.getValue());
        }

        private static Bom execAddFormulation(final ParsedArgs a) throws Exception {
            return addFormulation(a.getFileName(), a.getFormulaName());
        }

        private static Bom execAddFormulationComp(final ParsedArgs a) throws Exception {
            return addFormulationComp(a.getFileName(), a.getFormulaName(), a.getName(), a.getType());
        }

        private static Bom execAddFormulationCompProp(final ParsedArgs a) throws Exception {
            return addFormulationCompProp(a.getFileName(), a.getFormulaName(), a.getCompName(), a.getName(), a.getValue());
        }

        private static Bom execAddMetadataTools(final ParsedArgs a) throws Exception {
            return addMetadataTools(a.getFileName(), a.getTool(), a.getVersion());
        }

        private static Bom execAddComponent(final ParsedArgs a) throws Exception {
            return addComponent(a.getFileName(), a.getCompName(), a.getVersion(), a.getDescription());
        }

        private static Bom execAddComponentHash(final ParsedArgs a) throws Exception {
            return addComponentHash(a.getFileName(), a.getCompName(), a.getHash());
        }

        private static Bom execAddComponentProp(final ParsedArgs a) throws Exception {
            return addComponentProperty(a.getFileName(), a.getCompName(), a.getName(), a.getValue());
        }

        private static Bom execAddFormulaProp(final ParsedArgs a) throws Exception {
            return addFormulaProperty(a.getFileName(), a.getFormulaName(), a.getFormulaPropName(), a.getValue());
        }

        private static Bom execAddWorkflow(final ParsedArgs a) throws Exception {
            return addWorkflow(a.getFileName(), a.getFormulaName(), a.getWorkflowRef(), a.getWorkflowUid(), a.getWorkflowName(), a.getRawTaskTypes());
        }

        private static Bom execAddWorkflowStep(final ParsedArgs a) throws Exception {
            return addWorkflowStep(a.getFileName(), a.getFormulaName(), a.getWorkflowRef(), a.getWorkflowStepName(), a.getDescription());
        }

        private static Bom execAddWorkflowStepCmd(final ParsedArgs a) throws Exception {
            return addWorkflowStepCmd(a.getFileName(), a.getFormulaName(), a.getWorkflowRef(), a.getWorkflowStepName(), a.getExecuted());
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
