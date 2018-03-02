
import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileFilter;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.nio.file.Files;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.Collections;
import java.util.Comparator;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

/**
 *
 * @author jvanek
 */
public class MercurialTracker {

    //usually it is not necessary, but some chaotic repos, eg java-10-openjdk-shenandoah/hotspot, have branches with no tag at all. There it is exponential complexity, so the limit shoud be about 20, max 50... at 100 you may wait for ever.
    //it do nto hae reason to track lines longer then...20? 100?
    private static int MAX_BUFFER_LENGTH = Integer.MAX_VALUE;
    //private static int MAX_BUFFER_LENGTH = 20;
    private static File outputDir = null;
    private static BufferedWriter logFile = null;
    private static boolean removeDethTags = false;
    private static boolean ignoreNonDefaultBranches = false;
    private static boolean debug = false;
    private static boolean tiptags = false;
    private static boolean enforceSingle = false;
    private static final String TIP_MARKER = "tip";
    private static final String DEFAULT_BRANCH = "default";

    public static String getDethTagReason() {
        return "Size of path owergrown over " + MAX_BUFFER_LENGTH + ". Ignore this path";
    }

    private static final String switch_buffer = "-bufferLimit";
    private static final String switch_paths = "-removeUncompletePaths";
    private static final String switch_branches = "-ignoreNonDefaultBranches";
    private static final String switch_verbose = "-verbose";
    private static final String switch_output = "-outputDir";
    private static final String switch_tiptags = "-tipTagsOnly";
    private static final String switch_enforceSingle = "-enforceSingleRepo";
    private static final String switch_log = "-log";

    /**
     * This is trying to walk paralel mercurial lines, find tags, track it just
     * before its merge and marks it as "tip of tag's line". As second phase,
     * the tags reachable in some repos but not in others are searched in other
     * repos too. As last phase, the individual repos are connected to create
     * tag+numberOfchangesets sets of repo-checkout points.
     *
     *
     * @param args the command line arguments
     */
    public static void main(String[] args) throws IOException, InterruptedException, ParseException, NoPathFoundException {
        //needs maxbuffer, looks ok with 20, but repos cant bejoined
        //args = new String[]{"/home/jvanek/Desktop/jdks/clonned/java-10-openjdk"};
        //args = new String[]{"/home/jvanek/Desktop/jdks/clonned/java-10-openjdk-shenandoah"};
        //ok
        //args = new String[]{"/home/jvanek/Desktop/jdks/clonned/java-1.8.0-openjdk", switch_log + "=/tmp/aaa"};
        //args = new String[]{"/home/jvanek/Desktop/jdks/clonned/java-1.8.0-openjdk-aarch64"};
        //args = new String[]{"/home/jvanek/Desktop/jdks/clonned/java-1.8.0-openjdk-aarch64-shenandoah", switch_verbose, switch_tiptags};
        //args = new String[]{"/home/jvanek/Desktop/jdks/clonned/java-1.8.0-openjdk-dev"};
        //args = new String[]{"/home/jvanek/Desktop/jdks/clonned/java-9-openjdk"};

        if (args == null || args.length == 0) {
            System.out.println("You must specify hg repo/forest to scan. If forest, then you should have the individuall trees synchronised");
            System.out.println("Optional swithces are: ");
            System.out.println(" * " + switch_buffer);
            System.out.println("     This one expects value. eg " + switch_buffer + "=30");
            System.out.println("     it is setting the max depth of investigated path.");
            System.out.println("     Note that teh compelxity is exponential in this case, sostay at 10-30. With eg 100, you can keep ti unlimited anyway.");
            System.out.println("     Without it,some high-development forests like jdk10 or jdk10-shenandoah");
            System.out.println("     will run for many hours, and have unpredictable results");
            System.out.println("     If yuou need to use this switch, you probably do not need this program at all.");
            System.out.println(" * " + switch_paths);
            System.out.println("     Usually used with " + switch_buffer + " the paths not ending by tags wil be removed.");
            System.out.println("     And so, making the search even more useless.");
            System.out.println(" * " + switch_branches);
            System.out.println("     This will make crawling oinly on default branch. I dont know what it is for.");
            System.out.println(" * " + switch_verbose);
            System.out.println("     Enable more verbsoe output");
            System.out.println(" * " + switch_output);
            System.out.println("     This one expects value. eg " + switch_output + "=$PWD");
            System.out.println("     Insted of stdouting result, several files with individual contents will be generated.");
            System.out.println("     list of fiels will be stdouted.");
            System.out.println(" * " + switch_tiptags);
            System.out.println("     Will try to determine and stdout tag of tip only");
            System.out.println(" * " + switch_enforceSingle);
            System.out.println("     will prohibit searching for subrepos");
            System.out.println(" * " + switch_log);
            System.out.println("     will log stdout to logs. Results will be printed normally to stdout/file as set by above");
            System.out.println("     if log is file, it is is used, if it is directory, file named MercurialTracker-timestamp.log willbe created here");
            System.out.println("     This one expects value. eg " + switch_log + "=$PWD");
            System.exit(0);
        }
        String mainDir = null;
        for (String arg : args) {
            if (arg.startsWith(switch_buffer)) {
                MAX_BUFFER_LENGTH = Integer.valueOf(arg.split("=")[1]);
            } else if (arg.startsWith(switch_output)) {
                outputDir = new File(arg.split("=")[1]);
                if (!outputDir.exists()) {
                    throw new RuntimeException(outputDir + " does not exists");
                }
            } else if (arg.startsWith(switch_log)) {
                File logCandidate = new File(arg.split("=")[1]).getAbsoluteFile();
                if (logCandidate.exists() && logCandidate.isDirectory()) {
                    logCandidate = new File(logCandidate, "MercurialTracker-" + TagCommitRepo.isoOutput.format(new Date()) + ".log");
                    logFile = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(logCandidate), "utf-8"));
                    clsoeOnExit();
                } else if (!logCandidate.getParentFile().exists()) {
                    throw new RuntimeException(logCandidate.getName() + "'s  directory " + logCandidate.getParent() + " does not exists");
                } else {
                    logFile = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(logCandidate), "utf-8"));
                    clsoeOnExit();
                }
            } else if (arg.startsWith(switch_paths)) {
                removeDethTags = true;
            } else if (arg.startsWith(switch_branches)) {
                ignoreNonDefaultBranches = true;
            } else if (arg.startsWith(switch_verbose)) {
                debug = true;
            } else if (arg.startsWith(switch_tiptags)) {
                tiptags = true;
            } else if (arg.startsWith(switch_enforceSingle)) {
                enforceSingle = true;
            } else if (mainDir == null) {
                mainDir = arg;
            } else {
                throw new RuntimeException("You already set mainDir to " + mainDir);
            }
        }
        if (mainDir == null) {
            throw new RuntimeException("No mercurial directory specified!");
        }
        File topHg = new File(mainDir);
        if (tiptags) {
            //this is comletely separate task
            List<RepoWalker> logs = new ArrayList<>();
            logs.add(new RepoWalker(topHg));
            if (!enforceSingle) {
                File[] subrepos = findSubRepos(topHg);
                for (File subrepo : subrepos) {
                    logs.add(new RepoWalker(subrepo));
                }
            }
            List<TagWithDate> setOfAllTags = new ArrayList<>();
            for (RepoWalker log : logs) {
                int i = log.walkHgLog();
                if (i != 0) {
                    throw new RuntimeException("hg log returned nonzero - " + i);
                }
                addAllIfNewer(setOfAllTags, log.justListTags());
            }
            String directTag = filterDirectTags(findDirectTags(logs));
            if (directTag != null) {
                loglnResult(directTag);
                System.exit(0);
            }
            List<TagWithDate> allTags = new ArrayList<>(setOfAllTags);
            allTags.remove(new TagWithDate(TIP_MARKER, new Date()));

            Map<String, List<TagWithDate>> prefixedArrays = new HashMap<>();
            logln("-------------");
            Collections.sort(allTags);
            for (TagWithDate tag : allTags) {
                prefixedArrays.put(getTagPreffix(tag.tag), new ArrayList<>());
                logln(tag.toString());

            }
            logln("-------------");
            Collections.sort(allTags, new Comparator<TagWithDate>() {
                @Override
                public int compare(TagWithDate o1, TagWithDate o2) {
                    return tagSort(o1.tag, o2.tag);
                }
            });
            //we are keeping the individual lists sorted by tag here!
            for (TagWithDate tag : allTags) {
                List<TagWithDate> list = prefixedArrays.get(getTagPreffix(tag.tag));
                list.add(tag);
                logln(tag.tag + "  " + TagCommitRepo.isoOutput.format(tag.date));

            }
            logln("-------------");
            for (Map.Entry<String, List<TagWithDate>> prefix : prefixedArrays.entrySet()) {
                logln(prefix.getKey() + " - " + prefix.getValue().size());
            }
            logln("-------------");
            //trick again - we must sort to groups by non - numeric prefix and then find most fresh tops(reaso nicedtea tag x jdk tag or shenandoah tags...
            List<TagWithDate> winners = new ArrayList<>();
            for (Map.Entry<String, List<TagWithDate>> prefix : prefixedArrays.entrySet()) {
                for (TagWithDate tag : prefix.getValue()) {
                    tagIter:
                    {
                        for (RepoWalker log : logs) {
                            if (!log.verifyTag(tag.tag)) {
                                //tag not present in any repo, exiting
                                break tagIter;
                            }
                        }
                    }
                    winners.add(tag);
                    break;
                }
            }
            Collections.sort(winners);
            if (winners.isEmpty()) {
                throw new RuntimeException("No common tag found");
            }
            loglnResult(winners.get(0).tag);
            System.exit(0);
        }
        List<RepoCommitPathsSearch> repos = new ArrayList<>();
        RepoCommitPathsSearch rcps = new RepoCommitPathsSearch(mainDir);
        repos.add(rcps);
        rcps.findPaths();
        if (!enforceSingle) {
            File[] subrepos = findSubRepos(topHg);
            logln("Found " + subrepos.length);
            for (File subrepo : subrepos) {
                logln("Trying " + subrepo.getName());
                RepoCommitPathsSearch subrepoPaths = new RepoCommitPathsSearch(subrepo.getAbsolutePath());
                subrepoPaths.findPaths();
                repos.add(subrepoPaths);
            }
        }
        //complete missing tags
        for (RepoCommitPathsSearch repo1 : repos) {
            for (RepoCommitPathsSearch repo2 : repos) {
                repo1.addMisingTags(repo2);
            }
        }
        //find paths to missing tags
        for (RepoCommitPathsSearch repo : repos) {
            repo.findPathsToMissingTags();
        }
        logln("**************");
        if (repos.size() == 1) {
            RepoCommitPathsSearch repo = repos.get(0);
            List<TagCommitRepo> merged = repo.getMergedPaths();
            for (TagCommitRepo m : merged) {
                if (outputDir == null) {
                    loglnResult(formatTagAndChangesets(m.tag, m.changesetsSinceTag));
                    loglnResult("  " + constructFinalSentence(m));
                } else {
                    String fileName = formatTagAndChangesetsFileName(m.tag, m.changesetsSinceTag);
                    File f = new File(outputDir, fileName);
                    loglnResult(f.getAbsolutePath());
                    String content = constructFinalSentence(m);
                    try {
                        Files.write(f.toPath(), (content + System.getProperty("line.separator")).getBytes("utf-8"));
                    } catch (IOException e) {
                        e.printStackTrace();
                    }
                }
            }
            //single repo do not need more synhronization
            System.exit(0);
        }
        CommitsJoiner cj = new CommitsJoiner(new File(mainDir).getName());
        for (RepoCommitPathsSearch repo : repos) {
            List<TagCommitRepo> merged = repo.getMergedPaths();
            logln(merged.size() + ": (" + repo.subrepo + ")");
            for (TagCommitRepo result : merged) {
                logln(result.toString());

            }
            cj.addRepoCommits(merged);
        }
        //pair tags-commits among repos
        logln("------------");
        cj.printTags();
        logln("------------");
        cj.reductRepos();
        cj.printReducdRepos();

    }

    private static File[] findSubRepos(File topHg) {
        File[] subrepos = topHg.listFiles(new FileFilter() {
            @Override
            public boolean accept(File pathname) {
                return pathname.isDirectory() && Arrays.asList(pathname.list()).contains(".hg");
            }
        });
        return subrepos;
    }

    private static List<LogItem> getSortedListOfTags(List<PathInRepo> pathsToTags) {
        List<LogItem> tags = new ArrayList<>(pathsToTags.size());
        pathsToTags.stream().forEach((pathBuffer) -> {
            tags.add(pathBuffer.getTag());
        });
        Collections.sort(tags, new Comparator<LogItem>() {
            @Override
            public int compare(LogItem o1, LogItem o2) {
                if (o1.tag == null && o2.tag == null) {
                    return 0;
                }
                if (o1.tag == null && o2.tag != null) {
                    return -1;
                }
                if (o1.tag != null && o2.tag == null) {
                    return 1;
                }
                return tagSort(o1.tag, o2.tag);
            }

        });
        return tags;
    }

    private static boolean isMergeFatal(LogItem followingMerge, LogItem currentItem) {
        //merge is fatal, if it merges into other line
        //but not if somethig is merged to our line
        //most simple detection is order of parents.
        //if we come from first parent, its non fatal
        //if we come from second parent, our line is terminated
        if (followingMerge.parents.size() < 2) {
            //no merge
            return false;
        }
        if (followingMerge.parents.size() != 2) {
            throw new RuntimeException("more then two parents!");
        }
        if (followingMerge.parents.get(0).equals(currentItem.changeset)) {
            return false;
        }
        if (followingMerge.parents.get(1).equals(currentItem.changeset)) {
            return true;
        }
        throw new RuntimeException("Unreacahble merge");
    }

    private static void clsoeOnExit() {
        Runtime.getRuntime().addShutdownHook(new Thread() {
            @Override
            public void run() {
                try {
                    logFile.flush();
                    logFile.close();
                } catch (Exception ex) {
                    ex.printStackTrace();
                }
            }

        });
    }

    private static String filterDirectTags(Set<String> tags) {
        if (tags == null || tags.isEmpty() || tags.size() > 1) {
            return null;
        }
        return (String) (tags.toArray()[0]);
    }

    /**
     * This method searches for any tag *before* any possible split. If tag is
     * found here, it should be preffered to anything else.
     *
     * @param logs
     */
    private static Set<String> findDirectTags(List<RepoWalker> logs) {
        Set<String> result = new HashSet<>();
        for (RepoWalker log : logs) {
            TagWithDate i = findDirectTag(log);
            if (i == null) {
                return new HashSet<>();
            } else {
                result.add(i.tag);
            }
        }
        return result;
    }

    private static TagWithDate findDirectTag(RepoWalker log) {
        for (LogItem item : log.log) {
            if (item.tag != null && !item.tag.equals(TIP_MARKER)) {
                return new TagWithDate(item);
            }
            if (item.parents.size() > 1) {
                return null;
            }
        }
        return null;
    }

    private static class RepoWalker {

        private final File repo;
        private List<LogItem> log;

        public RepoWalker(File arg) {
            repo = arg;
        }

        private int walkHgLog() throws IOException, InterruptedException, ParseException {
            ProcessBuilder b = new ProcessBuilder("hg", "log");
            b.directory(repo);
            Process p = b.start();
            InputStream os = p.getInputStream();
            log = walkStreamOfHgLog(os);
            return p.waitFor();
        }

        private static List<LogItem> walkStreamOfHgLog(InputStream os) throws IOException, ParseException {
            List<LogItem> log = new ArrayList<>();
            BufferedReader br = new BufferedReader(new InputStreamReader(os, "utf-8"));
            LogItem currentLogItem = null;
            while (true) {
                String s = br.readLine();
                if (s == null) {
                    break;
                }
                if (s.trim().isEmpty() || currentLogItem == null) {
                    if (currentLogItem != null && currentLogItem.changeset.id == 0) {
                        //exiting on first logln, as mercurial logln is ending with empty space and we do nto wont tohave it added
                        break;
                    }
                    currentLogItem = new LogItem();
                    log.add(currentLogItem);
                }
                if (!s.trim().isEmpty()) {
                    boolean wasChangesetId = currentLogItem.addLine(s);
                    if (wasChangesetId) {
                        //for all items except first
                        int logsize = log.size();
                        if (logsize > 1) {
                            //current is logln.currentItem(logsize - 1)
                            LogItem lastLogItem = log.get(logsize - 2);
                            if (lastLogItem.parents.isEmpty()) {
                                lastLogItem.parents.add(currentLogItem.changeset);
                            }
                            //log(lastLogItem);
                        }
                    }
                }
            }
            //log(currentLogItem);
            return log;
        }

        private void createTree() {
            for (int i = 0; i < log.size(); i++) {
                LogItem currentItem = log.get(i);
                for (ChangesetId parent : currentItem.parents) {
                    for (int j = i + 1; j < log.size(); j++) {
                        LogItem possibleParent = log.get(j);
                        if (possibleParent.changeset.equals(parent)) {
                            currentItem.parentPointers.add(possibleParent);
                            possibleParent.childrenPointers.add(currentItem);
                            break;
                        }
                    }
                }
            }
        }

        private List<PathInRepo> findPathsWithTags() {
            LogItem tip = log.get(0);
            //we need to keep the pathBuffer how the tag was reached.
            //if only the final pathBuffer is returned, then we cannot track dowen the pathBuffer again,
            //as each node on path can have multiple children
            List<LogItem> buffer = new ArrayList<>();
            return findTags(tip, buffer, null, MAX_BUFFER_LENGTH);
        }

        private static boolean isDesired(LogItem item, Collection<String> targets) {
            if (targets == null) {
                return (item.tag != null && !item.tag.equals(TIP_MARKER));
            }
            if (item.tag != null) {
                //debuging optimalization, we do not wont to stop on each null tag commit
                return targets.contains(item.tag);
            } else {
                return false;
            }

        }

        /**
         * If performance issues rise, rewrote this to "breadth-first search"
         *
         * @param nodeBufferWithpathBuffers todo: As is common in breadth-first
         * search, the FIFO is needed to store the children. However, we have to
         * keep an path, how the node was reached, so we are remembering whole
         * path here
         */
        private static List<PathInRepo> findTags(LogItem item, List<LogItem> pathBuffer, Collection<String> targets, int usedMaxBufferLength) {
            if (ignoreNonDefaultBranches) {
                if (!item.branch.equals(DEFAULT_BRANCH)) {
                    return new ArrayList<>(0);
                }
            }
            pathBuffer.add(item);
            if (isDesired(item, targets) || pathBuffer.size() > usedMaxBufferLength) {
                List<PathInRepo> newResult = new ArrayList();
                PathInRepo pr;
                if (item.tag == null) {
                    pr = new PathInRepo(pathBuffer, true);
                } else {
                    pr = new PathInRepo(pathBuffer, false);
                }
                newResult.add(pr);
                pathBuffer.remove(item);
                return newResult;
            } else {
                List<PathInRepo> r = new ArrayList<>();
                List<LogItem> parents = item.parentPointers;
                //WARNING!
                //if you convert this to stream, then the recursion fails after depth of some 1000 !!!
                for (LogItem parent : parents) {
                    r.addAll(findTags(parent, pathBuffer, targets, usedMaxBufferLength));
                }
                pathBuffer.remove(item);
                return r;
            }
        }

        private List<PathInRepo> findPathsToTags(Collection<String> unreachableTags) {
            LogItem tip = log.get(0);
            //we need to keep the pathBuffer how the tag was reached.
            //if only the final pathBuffer is returned, then we cannot track dowen the pathBuffer again,
            //as each node on path can have multiple children
            List<LogItem> buffer = new ArrayList<>();
            int usedMaxBufferLength = MAX_BUFFER_LENGTH;
            if (usedMaxBufferLength == Integer.MAX_VALUE) {
                usedMaxBufferLength = 20;
            }
            return findTags(tip, buffer, unreachableTags, usedMaxBufferLength);
        }

        private boolean verifyTag(String unreachableTag) {
            for (LogItem item : log) {
                if (unreachableTag.equals(item.tag)) {
                    return true;
                }
            }
            return false;
        }

        private static final long year = 365l * 24l * 60l * 60l * 1000l;

        private List<TagWithDate> justListTags() {
            Date now = new Date();
            List<TagWithDate> r = new ArrayList<>();
            for (LogItem item : log) {
                if (item.tag != null) {
                    //limiting by year will get us rid of hs tags from jdk7
                    if (now.getTime() - item.dateParsed.getTime() > year) {
                        break;
                    }
                    addIfNewer(r, new TagWithDate(item));
                }
            }
            return r;
        }
    }

    private static class ChangesetId {

        private final String changeset;
        private final int id;
        private final String hghash;

        public ChangesetId(String s) {
            changeset = s;
            String[] ss = s.split(":");
            id = Integer.valueOf(ss[0]);
            hghash = ss[1];
        }

        @Override
        public String toString() {
            return id + ":" + hghash;
        }

        @Override
        public boolean equals(Object obj) {
            if (obj instanceof ChangesetId) {
                ChangesetId o = (ChangesetId) obj;
                return this.id == o.id && this.hghash.equals(o.hghash);
            }
            return false;
        }

        @Override
        public int hashCode() {
            int hash = 7;
            hash = 89 * hash + this.id;
            hash = 89 * hash + Objects.hashCode(this.hghash);
            return hash;
        }

    }

    private static class LogItem {

        private final SimpleDateFormat df = new SimpleDateFormat("EEE MMM dd HH:mm:ss yyyy ZZZZZ");
        private ChangesetId changeset;
        private String tag;
        private String user;
        private String date;
        private Date dateParsed;
        private String summary;
        private String branch = DEFAULT_BRANCH;
        //ususally 1-2 parents, no more, no less?
        private final List<ChangesetId> parents = new ArrayList<>(1);
        private final List<LogItem> parentPointers = new ArrayList<>(2);
        private final List<LogItem> childrenPointers = new ArrayList<>();

        public LogItem() {
        }

        /**
         *
         * @param s line to parse
         * @return true, if the parameter was changeset identificator, otherwise
         * false
         */
        private boolean addLine(String s) throws ParseException {
            String[] ss = s.split(":\\s+");
            switch (ss[0]) {
                case "changeset":
                    changeset = new ChangesetId(ss[1]);
                    return true;
                case "tag":
                    tag = ss[1];
                    return false;
                case "parent":
                    parents.add(new ChangesetId(ss[1]));
                    return false;
                case "user":
                    user = ss[1];
                    return false;
                case "date":
                    date = ss[1];
                    dateParsed = df.parse(date);
                    return false;
                case "summary":
                    summary = ss[1];
                    return false;
                case "branch":
                    branch = ss[1];
                    return false;
                default:
                    throw new RuntimeException("Unknow command of " + ss[1] + " in " + s);
            }

        }

        @Override
        public String toString() {
            StringBuilder b = new StringBuilder();
            b.append("changeset:    ")
                    .append(changeset.toString())
                    .append("\n" + "user:        ")
                    .append(user)
                    .append("\n" + "date:        ")
                    .append(date)
                    .append("\n" + "summary:     ")
                    .append(summary)
                    .append("\n" + "tag:         ")
                    .append(tag).append("\n");
            parents.stream().forEach((parent) -> {
                b.append("parent:       ")
                        .append(parent).append("\n");
            });
            return b.toString();

        }

    }

    private static class NoPathFoundException extends Exception {

        public NoPathFoundException() {
        }
    }

    private static class RepoCommitPathsSearch {

        private final String repo;
        private final String subrepo;
        private final RepoWalker walker;
        List<LogItem> reachableTipLines;
        List<LogItem> unreachableTipLines;
        List<TagCommitRepo> reachablePathsResults;
        List<TagCommitRepo> unreachablePathsResults;
        List<LogItem> reachableTags;
        private final Set<String> unreachableTags = new HashSet<>();
        List<PathInRepo> pathsToTags;
        List<PathInRepo> pathsToUnreachableTags;

        @Override
        public String toString() {
            return repo + "-" + subrepo;
        }

        private RepoCommitPathsSearch(File mainDir) {
            File parent = mainDir.getParentFile();
            if (new File(parent, ".hg").exists() && new File(mainDir, ".hg").exists()) {
                repo = parent.getName();
                subrepo = mainDir.getName();
            } else {
                repo = mainDir.getName();
                subrepo = mainDir.getName();
            }
            walker = new RepoWalker(mainDir);
        }

        private RepoCommitPathsSearch(String mainDir) {
            this(new File(mainDir));
        }

        public Set<String> getReachableTags() {
            Set<String> ss = new HashSet<>();
            for (LogItem s : reachableTags) {
                ss.add(s.tag);
            }
            return ss;
        }

        /**
         * This method fills several resulting fields for first iteration of
         * searching;
         *
         * @throws IOException
         * @throws MercurialTracker.NoPathFoundException
         * @throws InterruptedException
         * @throws ParseException
         */
        public void findPaths() throws IOException, NoPathFoundException, InterruptedException, ParseException {
            int i = walker.walkHgLog();
            if (i != 0) {
                throw new RuntimeException("hg log returned nonzero - " + i);
            }
            walker.createTree();
            pathsToTags = walker.findPathsWithTags();
            //remove invalid paths
            if (removeDethTags) {
                removeDeadEnds(pathsToTags);
            }

            if (pathsToTags.isEmpty()) {
                logln("No path found!");
                logln("Increase buffer length?");
                logln("Include dead branches?");
                logln("Simply clone tip and name it by timestamp?");
                throw new NoPathFoundException();
            }

            reachableTags = getSortedListOfTags(pathsToTags);
            for (LogItem tag : reachableTags) {
                logln(tag.tag + ": " + tag.changeset);

            }

            reachableTipLines = new ArrayList<>();
            unreachableTipLines = new ArrayList<>();
            reachablePathsResults = findTipsOfLines(pathsToTags, reachableTipLines);
            logln("-----------------");
            logln("most fresh tag: " + reachableTags.get(0).tag);
            logln("tip lines are (should be 1!): ");
            for (LogItem tipLine : reachableTipLines) {
                logln("  " + tipLine.tag + " " + tipLine.changeset + " " + tipLine.summary);

            }

            Collections.sort(reachablePathsResults);
            for (TagCommitRepo allResult : reachablePathsResults) {
                logln(allResult.toString());

            }
        }

        private static void removeDeadEnds(List<PathInRepo> pathsToTags) {
            for (int j = 0; j < pathsToTags.size(); j++) {
                PathInRepo path = pathsToTags.get(j);
                if (path.overflow) {
                    pathsToTags.remove(path);
                    j--;
                }
            }
        }

        private void addMisingTags(RepoCommitPathsSearch fromRepo) {
            for (String s : fromRepo.getReachableTags()) {
                if (!getReachableTags().contains(s)) {
                    unreachableTags.add(s);
                }
            }
        }

        private void findPathsToMissingTags() {
            Set<String> locallyReachableTags = new HashSet<>();
            for (String t : unreachableTags) {
                boolean b = walker.verifyTag(t);
                if (b) {
                    locallyReachableTags.add(t);
                } else {
                    loglnError("Warning! Searched tag " + t + " not found in " + repo + "/" + subrepo);
                    //throw new RuntimeException("Tag " + t + " not found in " + topRepoName + "/" + subrepo);
                }
            }
            pathsToUnreachableTags = walker.findPathsToTags(locallyReachableTags);
            //in case of limmited depth, we need to filter out garbage
            for (int i = 0; i < pathsToUnreachableTags.size(); i++) {
                PathInRepo get = pathsToUnreachableTags.get(i);
                if (get.getTag() == null) {
                    pathsToUnreachableTags.remove(i);
                    i--;
                    continue;
                }

                if (!unreachableTags.contains(get.getTag().tag)) {
                    pathsToUnreachableTags.remove(i);
                    i--;
                    continue;
                }

            }
            unreachablePathsResults = findTipsOfLines(pathsToUnreachableTags, new ArrayList<>());
            //secondary walkthrough can bring in false tips
            for (int i = 0; i < unreachablePathsResults.size(); i++) {
                TagCommitRepo get = unreachablePathsResults.get(i);
                if (get.tipLine) {
                    unreachablePathsResults.remove(i);
                    i--;
                }

            }
            Collections.sort(unreachablePathsResults);
            for (TagCommitRepo q : unreachablePathsResults) {
                q.wasAdded = true;
            }
        }

        private List<TagCommitRepo> findTipsOfLines(List<PathInRepo> pathsToTags, List<LogItem> tipLines) {
            List<TagCommitRepo> result = new ArrayList<>(pathsToTags.size());
            //TODO handle case when no valid tag is found
            for (PathInRepo pathBuffer : pathsToTags) {
                logln("-----------------");
                if (pathBuffer.overflow) {
                    logln(getDethTagReason());
                }
                int taggedTopOfPath = pathBuffer.size() - 1;
                boolean wasLineKillingMerge = false;
                //>=1, as the last meemebr have no reson in this cycle
                for (int j = taggedTopOfPath; j >= 1; j--) {
                    LogItem logItem = pathBuffer.get(j);
                    LogItem prevItem = pathBuffer.get(j - 1);
                    if (prevItem.summary.equals("Merge") && !wasLineKillingMerge) {
                        if (isMergeFatal(prevItem, logItem)) {
                            log(" * ");
                            result.add(pathBuffer.toResult(j, repo, subrepo, prevItem));
                            wasLineKillingMerge = true;
                        }
                    }
                    logln(logItem.tag + " " + logItem.changeset + " " + logItem.summary);
                }
                int j = 0;
                LogItem logItem = pathBuffer.get(j);
                //no killing merge found? Main line! Mark the tip!
                if (TIP_MARKER.equals(logItem.tag) && !wasLineKillingMerge) {
                    log(" * ");
                    result.add(pathBuffer.toResult(j, repo, subrepo, logItem));
                    tipLines.add(pathBuffer.get(pathBuffer.size() - 1));
                }
                logln(logItem.tag + " " + logItem.changeset + " " + logItem.summary);
            }
            return result;
        }

        private List<TagCommitRepo> getMergedPaths() {
            List<TagCommitRepo> r = new ArrayList<>(reachablePathsResults.size() + unreachablePathsResults.size());
            r.addAll(reachablePathsResults);
            r.addAll(unreachablePathsResults);
            Collections.sort(r);
            //for max_buffer truncated paths
            for (int i = 0; i < r.size(); i++) {
                TagCommitRepo get = r.get(i);
                if (get.tag == null) {
                    r.remove(i);
                    i--;
                }

            }
            return r;
        }
    }

    private static class PathInRepo {

        private final List<LogItem> path;
        private final boolean overflow;

        private PathInRepo(List<LogItem> pathBuffer, boolean b) {
            List<LogItem> ppath = new ArrayList<>(pathBuffer);
            path = Collections.unmodifiableList(ppath);
            overflow = b;
        }

        private LogItem getTag() {
            return path.get(path.size() - 1);
        }

        private int size() {
            return path.size();
        }

        private LogItem get(int j) {
            return path.get(j);
        }

        private TagCommitRepo toResult(int checkoutIndex, String repo, String subrepo, LogItem mergeOrTip) {
            LogItem commit = get(checkoutIndex);
            LogItem tag = getTag();
            return new TagCommitRepo(tag.tag, commit.changeset, repo, subrepo, TIP_MARKER.equals(commit.tag), size() - checkoutIndex - 1, mergeOrTip.dateParsed);
        }
    }

    private static class TagCommitRepo implements Comparable<TagCommitRepo> {

        private final String tag;
        private final ChangesetId checkout;
        private final String repo;
        private final String subrepo;
        private final boolean tipLine;
        private final int changesetsSinceTag;
        private final Date mergeDate;
        private static final SimpleDateFormat isoOutput = new SimpleDateFormat("yyyy-MM-dd_HH:mm:ss_ZZZZ");
        private boolean wasAdded = false;

        public TagCommitRepo(String tag, ChangesetId checkout, String repo, String subrepo, boolean tipLine, int chst, Date mergeDate) {
            this.tag = tag;
            this.checkout = checkout;
            this.repo = repo;
            this.subrepo = subrepo;
            this.tipLine = tipLine;
            this.changesetsSinceTag = chst;
            this.mergeDate = mergeDate;

        }

        @Override
        public boolean equals(Object obj) {
            if (obj instanceof TagCommitRepo) {
                TagCommitRepo tt = (TagCommitRepo) obj;
                return tt.tag.equals(this.tag)
                        && tt.checkout.equals(this.checkout)
                        && tt.repo.equals(this.repo)
                        && tt.subrepo.equals(this.subrepo);
            } else {
                return false;
            }
        }

        @Override
        public int hashCode() {
            int hash = 7;
            hash = 83 * hash + Objects.hashCode(this.tag);
            hash = 83 * hash + Objects.hashCode(this.checkout);
            hash = 83 * hash + Objects.hashCode(this.repo);
            hash = 83 * hash + Objects.hashCode(this.subrepo);
            return hash;
        }

        @Override
        public String toString() {
            String s = getAdded() + " " + repo + " " + subrepo + " " + tag + " " + changesetsSinceTag + " " + checkout + " " + isoOutput.format(mergeDate);
            if (tipLine) {
                return s + " " + TIP_MARKER;
            } else {
                return s;
            }
        }

        @Override
        public int compareTo(TagCommitRepo o) {
            int r1 = tagSort(tag, o.tag);
            if (r1 == 0) {
                return o.changesetsSinceTag - changesetsSinceTag;
            } else {
                return r1;
            }
        }

        private String getAdded() {
            if (wasAdded) {
                return "secondary";
            } else {
                return "         ";
            }
        }

    }

    private static int tagSort(String o1, String o2) throws NumberFormatException {
        if (o1 == null && o2 == null) {
            return 0;
        }
        if (o1 != null && o2 == null) {
            return -1;
        }
        if (o1 == null && o2 != null) {
            return 1;
        }
        String[] oo1 = o1.split("[^0-9]+");
        String[] oo2 = o2.split("[^0-9]+");
        int min = Math.min(oo1.length, oo2.length);
        //first (0) is always empty string
        for (int j = 1; j < min; j++) {
            int a = Integer.valueOf(oo1[j]);
            int b = Integer.valueOf(oo2[j]);
            if (a != b) {
                return b - a;
            }
        }
        //longer is better! (aarch64/shenandoah prefixes)
        return -oo2.length + oo1.length;
    }

    private static void logln(String s) {
        if (logFile != null) {
            try {
                logFile.write(s);
                logFile.newLine();
            } catch (IOException ex) {
                ex.printStackTrace();
            }
        }
        if (debug) {
            System.out.println(s);
        }
    }

    private static void loglnError(String s) {
        System.err.println(s);
    }

    private static void log(String s) {
        if (logFile != null) {
            try {
                logFile.write(s);
            } catch (IOException ex) {
                ex.printStackTrace();
            }
        }
        if (debug) {
            System.out.print(s);
        }
    }

    private static void loglnResult(String s) {
        if (logFile != null) {
            try {
                logFile.write(s);
                logFile.newLine();
            } catch (IOException ex) {
                ex.printStackTrace();
            }
        }
        System.out.println(s);

    }

    private static class CommitsJoiner {

        private final String topRepoName;
        private final List<List<TagCommitRepo>> repos = new ArrayList<>();
        private final Map<String, Integer> tagsWithMinimalCount = new HashMap<>();
        private List<Map.Entry<String, Integer>> sortedSetOfTagsWithOccurences;
        private List<List<TagCommitRepo>> reducedRepos;

        public void printTags() {
            for (Map.Entry<String, Integer> entry : sortedSetOfTagsWithOccurences) {
                logln(entry.getKey() + ": " + entry.getValue());
            }
        }

        public void printReducdRepos() {
            //all reduced repos MUST have same size
            int l = reducedRepos.get(0).size();
            for (int i = 0; i < l; i++) {
                int changesets = 0;
                for (List<TagCommitRepo> repo : reducedRepos) {
                    TagCommitRepo get = repo.get(i);
                    changesets += get.changesetsSinceTag;
                }
                if (outputDir == null) {
                    loglnResult(formatTagAndChangesets(reducedRepos.get(0).get(i).tag, changesets));
                    for (List<TagCommitRepo> repo : reducedRepos) {
                        TagCommitRepo get = repo.get(i);
                        loglnResult("  " + constructFinalSentence(get));
                    }
                } else {
                    String fileName = formatTagAndChangesetsFileName(reducedRepos.get(0).get(i).tag, changesets);
                    File f = new File(outputDir, fileName);
                    loglnResult(f.getAbsolutePath());
                    StringBuilder content = new StringBuilder();
                    for (List<TagCommitRepo> repo : reducedRepos) {
                        TagCommitRepo get = repo.get(i);
                        content.append(constructFinalSentence(get)).append(System.getProperty("line.separator"));
                    }
                    try {
                        Files.write(f.toPath(), content.toString().getBytes("utf-8"));
                    } catch (IOException e) {
                        e.printStackTrace();
                    }

                }
            }
        }

        public void reductRepos() {
            //we have to limit occurence of each tag to its minimal occurence in all repos
            reducedRepos = new ArrayList<>(repos.size());
            for (List<TagCommitRepo> repo : repos) {
                List<TagCommitRepo> reducedRepo = new ArrayList<>();
                reducedRepos.add(reducedRepo);
                //for each repo we will gather tags one by one, but copy only the minimal occurences
                for (Map.Entry<String, Integer> tag : sortedSetOfTagsWithOccurences) {
                    ArrayList<TagCommitRepo> itemsofCurrentTag = new ArrayList();
                    for (TagCommitRepo item : repo) {
                        if (itemsofCurrentTag.size() >= tag.getValue()) {
                            break;
                        }
                        if (tag.getKey().equals(item.tag)) {
                            itemsofCurrentTag.add(item);
                        }
                    }
                    reducedRepo.addAll(itemsofCurrentTag);
                }
            }
        }

        public CommitsJoiner(String repo) {
            this.topRepoName = repo;
        }

        public void addRepoCommits(List<TagCommitRepo> sortedPossiblePoints) {
            if (sortedPossiblePoints.isEmpty()) {
                throw new RuntimeException("There is repo in " + topRepoName + " with no path - I guess you have max buffer enabled. That means some (main in this repo) line was to bussy and have more commits upto first tag then is your maxbuffer. Sorry no workaround for you,a s enlarging max buffer will increase time expentionally.");
            }
            repos.add(sortedPossiblePoints);
            Map<String, Integer> countsOfTags = new HashMap<>();
            //gather occurences of all tags
            for (TagCommitRepo point : sortedPossiblePoints) {
                if (!point.repo.equals(topRepoName)) {
                    throw new RuntimeException("Adding foreign repo " + point.repo + " to our " + topRepoName + " is not allowed");
                }
                Integer i = countsOfTags.get(point.tag);
                if (i == null) {
                    countsOfTags.put(point.tag, 1);
                } else {
                    countsOfTags.put(point.tag, i + 1);
                }
            }
            //record minimal occurence
            Set<Map.Entry<String, Integer>> occurences = countsOfTags.entrySet();
            for (Map.Entry<String, Integer> occurence : occurences) {
                Integer i = tagsWithMinimalCount.get(occurence.getKey());
                if (i == null) {
                    tagsWithMinimalCount.put(occurence.getKey(), occurence.getValue());
                } else if (occurence.getValue() < i) {
                    tagsWithMinimalCount.put(occurence.getKey(), occurence.getValue());
                }
            }
            sortedSetOfTagsWithOccurences = new ArrayList<>(tagsWithMinimalCount.entrySet());
            Collections.sort(sortedSetOfTagsWithOccurences, new Comparator<Map.Entry<String, Integer>>() {
                @Override
                public int compare(Map.Entry<String, Integer> o1, Map.Entry<String, Integer> o2) {
                    return tagSort(o1.getKey(), o2.getKey());
                }
            });
            //FIXME when max_buffer is used, there is bug, that tags not present in all repos can be ocunted in
            //1) dont use this to repos needeing max_buffer
            //2) fix this behavior so it is nt fatal, as tip is usually usable
        }
    }

    private static String constructFinalSentence(TagCommitRepo get) {
        String s = get.subrepo + " " + get.checkout;
        if (get.tipLine) {
            s = s + " tip";
        }
        return s;
    }

    private static String formatTagAndChangesets(String tag, int changesets) {
        return nvraprep(tag) + "-" + changesets;
    }

    private static String formatTagAndChangesetsFileName(String tag, int changesets) {
        return formatTagAndChangesets(tag, changesets) + ".changesets";
    }

    private static String nvraprep(String tag) {
        return tag.replaceAll("[^0-9a-zA-Z]+", ".");
    }

    private static class TagWithDate implements Comparable<TagWithDate> {

        private final String tag;
        private final Date date;

        @Override
        public String toString() {
            return tag + "  " + TagCommitRepo.isoOutput.format(date);
        }

        public TagWithDate(String tag, Date date) {
            this.tag = tag;
            this.date = date;
        }

        private TagWithDate(LogItem item) {
            this.tag = item.tag;
            this.date = item.dateParsed;
        }

        @Override
        public int hashCode() {
            return tag.hashCode();
        }

        @Override
        public boolean equals(Object obj) {
            if (this == obj) {
                return true;
            }
            if (obj == null) {
                return false;
            }
            if (getClass() != obj.getClass()) {
                return false;
            }
            final TagWithDate other = (TagWithDate) obj;
            if (!Objects.equals(this.tag, other.tag)) {
                return false;
            }
            return true;
        }

        @Override
        public int compareTo(TagWithDate o) {
            if (o.date.getTime() > this.date.getTime()) {
                return 1;
            }
            if (o.date.getTime() < this.date.getTime()) {
                return -1;
            }
            return 0;

        }

    }

    private static void addIfNewer(List<TagWithDate> r, TagWithDate candidate) {
        //keeping only newest version of tag
        int i = r.indexOf(candidate);
        if (i >= 0) {
            TagWithDate old = r.remove(i);
            if (candidate.date.getTime() > old.date.getTime()) {
                r.add(candidate);
            } else {
                r.add(old);
            }
        } else {
            r.add(candidate);
        }
    }

    private static void addAllIfNewer(List<TagWithDate> destination, List<TagWithDate> source) {
        for (TagWithDate tagWithDate : source) {
            addIfNewer(destination, tagWithDate);

        }
    }

    private static String getTagPreffix(String o1) throws NumberFormatException {
        if (o1 == null) {
            return null;
        }
        String[] oo1 = o1.split("[0-9]+");
        if (oo1.length == 0) {
            return o1;
        }
        return oo1[0];
    }

}
