/*
 * RsyncTask.vala
 *
 * Copyright 2012-18 Tony George <teejeetech@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA 02110-1301, USA.
 *
 *
 */

using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.JsonHelper;
using TeeJee.ProcessHelper;
using TeeJee.System;
using TeeJee.Misc;

public class RsyncTask : AsyncTask{

	// settings
	public string source_path = "";
	public string dest_path = "";

	public bool dry_run = false;
	public bool delete_extra = false;
	public bool delete_after = false;
	public bool delete_excluded = false;
	public bool relative = false;
	public bool remove_source_files = false;
	public bool skip_permissions_and_group = false;
	
	public string rsync_log_file = "";
	public string exclude_from_file = "";
	public string link_from_path = "";
	
	public bool verbose = true;
	public bool io_nice = true;
	public bool show_progress = true;

	public Gee.ArrayList<string> exclude_list;

	// status
	public GLib.Queue<string> status_lines;
	public int64 status_line_count = 0;
	public int64 total_size = 0;

	public int64 count_created;
	public int64 count_deleted;
	public int64 count_modified;
	public int64 count_checksum;
	public int64 count_size;
	public int64 count_timestamp;
	public int64 count_permissions;
	public int64 count_owner;
	public int64 count_group;
	public int64 count_unchanged;
	
	public RsyncTask(){
		init_regular_expressions();
		status_lines = new GLib.Queue<string>();
		exclude_list = new Gee.ArrayList<string>();
	}

	private void init_regular_expressions(){
		if (regex_list != null){
			return; // already initialized
		}
		
		regex_list = new Gee.HashMap<string,Regex>();
		
		try {
			//Example: status=-1
			regex_list["status"] = new Regex(
				"""(.)(.)(c|\+|\.| )(s|\+|\.| )(t|\+|\.| )(p|\+|\.| )(o|\+|\.| )(g|\+|\.| )(u|\+|\.| )(a|\+|\.| )(x|\+|\.| ) (.*)""");

			regex_list["created"] = new Regex(
				"""(.)(.)\+\+\+\+\+\+\+\+\+ (.*)""");

			regex_list["log-created"] = new Regex(
				"""[0-9/]+ [0-9:.]+ \[[0-9]+\] (.)(.)\+\+\+\+\+\+\+\+\+ (.*)""");
				
			regex_list["deleted"] = new Regex(
				"""\*deleting[ \t]+(.*)""");

			regex_list["log-deleted"] = new Regex(
				"""[0-9/]+ [0-9:.]+ \[[0-9]+\] \*deleting[ \t]+(.*)""");

			regex_list["modified"] = new Regex(
				"""(.)(.)(c|\+|\.| )(s|\+|\.| )(t|\+|\.| )(p|\+|\.| )(o|\+|\.| )(g|\+|\.| )(u|\+|\.| )(a|\+|\.| )(x|\+|\.) (.*)""");

			regex_list["log-modified"] = new Regex(
				"""[0-9/]+ [0-9:.]+ \[[0-9]+\] (.)(.)(c|\+|\.| )(s|\+|\.| )(t|\+|\.| )(p|\+|\.| )(o|\+|\.| )(g|\+|\.| )(u|\+|\.| )(a|\+|\.| )(x|\+|\.) (.*)""");

			regex_list["unchanged"] = new Regex(
				"""(.)(.)          (.*)""");

			regex_list["log-unchanged"] = new Regex(
				"""[0-9/]+ [0-9:.]+ \[[0-9]+\] (.)(.)\+\+\+\+\+\+\+\+\+ (.*)""");
				
			regex_list["total-size"] = new Regex(
				"""total size is ([0-9,]+)[ \t]+speedup is [0-9.]+""");
				
			// 305,002,533  80%   65.69MB/s    0:00:01  xfr#1653, ir-chk=1593/3594)
			//  417923072   9%   99.71MB/s    0:00:38
			regex_list["progress"] = new Regex(
				"""^[ \t]*([0-9,]+)[ \t]+([0-9.]+)%[ \t]+([0-9.a-zA-Z\/s]+)[ \t]+([0-9:.]+)""");
		}
		catch (Error e) {
			log_error (e.message);
		}
	}
	
	public void prepare() {
		string script_text = build_script();
		
		log_debug(script_text);
		
		save_bash_script_temp(script_text, script_file);
		log_debug("RsyncTask:prepare(): saved: %s".printf(script_file));

		//status_lines = new GLib.Queue<string>();
		status_line_count = 0;
		total_size = 0;

		count_created = 0;
		count_deleted = 0;
		count_modified = 0;
		count_checksum = 0;
		count_size = 0;
		count_timestamp = 0;
		count_permissions = 0;
		count_owner = 0;
		count_group = 0;
		count_unchanged = 0;
	}

	private string build_script() {
		var cmd = "";

		if (io_nice){
			//cmd += "ionice -c2 -n7 ";
		}

		cmd += "rsync -aii --recursive";

		if (skip_permissions_and_group){
			cmd += " --no-p --no-g";
		}
		
		if (verbose){
			cmd += " --verbose";
		}
		else{
			cmd += " --quiet";
		}

		if (delete_extra){
			cmd += " --delete";
		}

		if (delete_after){
			cmd += " --delete-after";
		}

		if (remove_source_files){
			cmd += " --remove-source-files";
		}

		if (dry_run){
			cmd += " --dry-run";
		}

		cmd += " --force"; // allow deletion of non-empty directories

		//cmd += " --numeric-ids";

		cmd += " --stats";

		//if (relative){
		//	cmd += " --relative";
		//}
		
		if (delete_excluded){
			cmd += " --delete-excluded";
		}
		
		if (link_from_path.length > 0){
			if (!link_from_path.has_suffix("/")){
				link_from_path = "%s/".printf(link_from_path);
			}
			
			cmd += " --link-dest='%s'".printf(escape_single_quote(link_from_path));
		}
		
		if (rsync_log_file.length > 0){
			cmd += " --log-file='%s'".printf(escape_single_quote(rsync_log_file));
		}

		string txt = "";
		foreach(string pattern in exclude_list){
			txt += "%s\n".printf(pattern);
		}

		log_debug(string.nfill(80,'-'));
		log_debug("Exclude Patterns:\n%s".printf(txt));
		log_debug(string.nfill(80,'-'));
		
		if (txt.length > 0){
			exclude_from_file = path_combine(working_dir, "filter.list");
			file_write(exclude_from_file, txt);
		}

		if (exclude_from_file.length > 0){
			cmd += " --exclude-from='%s'".printf(escape_single_quote(exclude_from_file));
			if (delete_extra && delete_excluded){
				cmd += " --delete-excluded";
			}
		}

		if (show_progress){
			cmd += " --info=progress2 --no-i-r --no-h";
		}

		source_path = remove_trailing_slash(source_path);
		
		dest_path = remove_trailing_slash(dest_path);
		
		cmd += " '%s/'".printf(escape_single_quote(source_path));

		cmd += " '%s/'".printf(escape_single_quote(dest_path));

		return cmd;
	}

	public FileItem parse_log(string log_file_path){
		var root = new FileItem.dummy_root();

		string log_file = log_file_path;
		DataOutputStream dos_changes = null;
		
		if (!log_file.has_suffix("-changes")){
			
			string log_file_changes = log_file_path + "-changes";
			
			if (file_exists(log_file_changes)){
				// use it
				log_file = log_file_changes;
			}
			else{
				// create one by initializing dos_changes
				try {
					var file = File.new_for_path(log_file_changes);
					if (file.query_exists()){
						file.delete();
					}
					var file_stream = file.create (FileCreateFlags.REPLACE_DESTINATION);
					dos_changes = new DataOutputStream (file_stream);
				}
				catch (Error e) {
					log_error (e.message);
				}
			}
		}

		log_debug("RsyncTask: parse_log()");
		log_debug("log_file = %s".printf(log_file));

		prg_count = 0;
		prg_count_total = file_line_count(log_file);

		try {
			string line;
			var file = File.new_for_path(log_file);
			if (!file.query_exists ()) {
				log_error(_("File not found") + ": %s".printf(log_file));
				return root;
			}

			var dis = new DataInputStream (file.read());
			while ((line = dis.read_line (null)) != null) {

				prg_count++;
				
				if (line.strip().length == 0) { continue; }

				string item_path = "";
				var item_type = FileType.REGULAR;
				string item_status = "";
				bool item_is_symlink = false;
				
				MatchInfo match;
				if (regex_list["log-created"].match(line, 0, out match)) {

					if (dos_changes != null){
						dos_changes.put_string("%s\n".printf(line));
					}
		
					//log_debug("matched: created:%s".printf(line));
					
					item_path = match.fetch(3).split(" -> ")[0].strip();
					item_type = FileType.REGULAR;
					if (match.fetch(2) == "d"){
						item_type = FileType.DIRECTORY;
					}
					else if (match.fetch(2) == "L"){
						item_is_symlink = true;
					}
					item_status = "created";
				}
				else if (regex_list["log-deleted"].match(line, 0, out match)) {
					
					//log_debug("matched: deleted:%s".printf(line));

					if (dos_changes != null){
						dos_changes.put_string("%s\n".printf(line));
					}
					
					item_path = match.fetch(1).split(" -> ")[0].strip();
					item_type = item_path.has_suffix("/") ? FileType.DIRECTORY : FileType.REGULAR;
					item_status = "deleted";
				}
				else if (regex_list["log-modified"].match(line, 0, out match)) {

					//log_debug("matched: modified:%s".printf(line));

					if (dos_changes != null){
						dos_changes.put_string("%s\n".printf(line));
					}
					
					item_path = match.fetch(12).split(" -> ")[0].strip();
					
					if (match.fetch(2) == "d"){
						item_type = FileType.DIRECTORY;
					}
					else if (match.fetch(2) == "L"){
						item_is_symlink = true;
					}
					
					if (match.fetch(3) == "c"){
						item_status = "checksum";
					}
					else if (match.fetch(4) == "s"){
						item_status = "size";
					}
					else if (match.fetch(5) == "t"){
						item_status = "timestamp";
					}
					else if (match.fetch(6) == "p"){
						item_status = "permissions";
					}
					else if (match.fetch(7) == "o"){
						item_status = "owner";
					}
					else if (match.fetch(8) == "g"){
						item_status = "group";
					}
				}
				else{
					//log_debug("not-matched: %s".printf(line));
				}
				
				if ((item_path.length > 0) && (item_path != "/./") && (item_path != "./")
					//&& ((item_type == FileType.REGULAR)||(item_status == "created"))
					){
						
					int64 item_size = 0;//int64.parse(size);
					string item_disk_path = path_combine(file_parent(log_file_path),"localhost");
					item_disk_path = path_combine(item_disk_path, item_path);
					item_size = file_get_size(item_disk_path);
					if (item_size == -1){
						item_size = 0;
					}
					
					var item = root.add_descendant(item_path, item_type, item_size, 0);
					item.file_status = item_status;
					item.is_symlink = item_is_symlink;
					//log_debug("added: %s".printf(item_path));
				}
				
			}
		}
		catch (Error e) {
			log_error (e.message);
		}

		if (dos_changes != null){
			// archive the raw log file
			file_gzip(log_file_path);
		}

		log_debug("RsyncTask: parse_log(): exit");
		
		return root;
	}

	public string add_rule_exclude(string file_path, bool is_directory){
		return add_rule(file_path, is_directory, false);
	}

	public string add_rule_include(string file_path, bool is_directory){
		return add_rule(file_path, is_directory, true);
	}

	public void add_rule_exclude_others(){
		exclude_list.add("*");
	}
	
	private string add_rule(string file_path, bool is_directory, bool include){

		string relative_path = "";
		if (file_path.has_prefix(source_path)){
			relative_path = file_path[source_path.length + 1: file_path.length];
		}
		else{
			relative_path = file_path;
		}

		relative_path = relative_path.replace("*","\\*").replace("?","\\?").replace("#","\\#").replace("[","\\[").replace("]","\\]");

		string pattern = "%s%s%s".printf((include ? "+ " : ""), relative_path, (is_directory ? "/***" : ""));
		exclude_list.add(pattern);
		
		return pattern;
	}
	
	// execution ----------------------------

	public void execute() {
		
		log_debug("RsyncTask:execute()");
		
		prepare();

		/*log_debug(string.nfill(70,'='));
		log_debug(script_file);
		log_debug(string.nfill(70,'='));
		log_debug(file_read(script_file));
		log_debug(string.nfill(70,'='));*/
		
		begin();

		if (status == AppStatus.RUNNING){
			
			
		}
	}

	public override void parse_stdout_line(string out_line){
		if (is_terminated) {
			return;
		}
		
		update_progress_parse_console_output(out_line);
	}
	
	public override void parse_stderr_line(string err_line){
		if (is_terminated) {
			return;
		}
		
		//update_progress_parse_console_output(err_line);
	}

	public bool update_progress_parse_console_output (string line) {
		if ((line == null) || (line.length == 0)) {
			return true;
		}

		mutex_parser.lock();

		status_line_count++;

		if (prg_count_total > 0){
			prg_count = status_line_count;
			progress = (prg_count * 1.0) / prg_count_total;
		}
		
		//MatchInfo match;
		//if (regex_list["status"].match(line, 0, out match)) {
		//	status_line = match.fetch(12);

			//status_lines.push_tail(status_line);
			//if (status_lines.get_length() > 15){
			//	status_lines.pop_head();
			//}
		//}
		MatchInfo match;
		if (regex_list["created"].match(line, 0, out match)) {

			//log_debug("matched: created:%s".printf(line));
			
			count_created++;
			status_line = match.fetch(3).split(" -> ")[0].strip();
		}
		else if (regex_list["deleted"].match(line, 0, out match)) {
			
			//log_debug("matched: deleted:%s".printf(line));

			count_deleted++;
			status_line = match.fetch(1).split(" -> ")[0].strip();
		}
		else if (regex_list["unchanged"].match(line, 0, out match)) {
			
			//log_debug("matched: deleted:%s".printf(line));

			count_unchanged++;
			status_line = match.fetch(3).split(" -> ")[0].strip();
		}
		else if (regex_list["modified"].match(line, 0, out match)) {

			//log_debug("matched: modified:%s".printf(line));

			count_modified++;
			status_line = match.fetch(12).split(" -> ")[0].strip();
			
			if (match.fetch(3) == "c"){
				count_checksum++;
			}
			else if (match.fetch(4) == "s"){
				count_size++;
			}
			else if (match.fetch(5) == "t"){
				count_timestamp++;
			}
			else if (match.fetch(6) == "p"){
				count_permissions++;
			}
			else if (match.fetch(7) == "o"){
				count_owner++;
			}
			else if (match.fetch(8) == "g"){
				count_group++;
			}
			else{
				count_unchanged++;
			}
		}
		else if (regex_list["total-size"].match(line, 0, out match)) {
			total_size = int64.parse(match.fetch(1).replace(",",""));
		}
		else if (regex_list["progress"].match(line, 0, out match)) {
			prg_bytes = int64.parse(match.fetch(1).replace(",",""));
			percent = double.parse(match.fetch(2));
			progress = percent / 100.0;
			prg_bytes_total = (int64) (prg_bytes * (100.0 / percent));
			rate = match.fetch(3);
			eta = match.fetch(4);
			stats_line = "%s / %s complete (%.0f%%), speed: %s, remaining: %s".printf(
				format_file_size(prg_bytes), format_file_size(prg_bytes_total), percent, rate, eta);
		}
		else{
			log_debug("rsync: %s".printf(line));
		}

		mutex_parser.unlock();

		return true;
	}

	protected override void finish_task(){
		if ((status != AppStatus.CANCELLED) && (status != AppStatus.PASSWORD_REQUIRED)) {
			status = AppStatus.FINISHED;
		}
	}

	public int read_status(){
		var status_file = working_dir + "/status";
		var f = File.new_for_path(status_file);
		if (f.query_exists()){
			var txt = file_read(status_file);
			return int.parse(txt);
		}
		return -1;
	}

	public string stats{
		owned get {

			string txt = "";

			txt += "%s".printf(format_file_size(prg_bytes));

			if (prg_bytes_total > 0){
				txt += " / %s".printf(format_file_size(prg_bytes_total));
			}

			txt += " %s".printf(_("transferred"));
			
			txt += " (%.0f%%),".printf(progress * 100.0);

			txt += " %s,".printf(rate);

			txt += " %s elapsed,".printf(stat_time_elapsed);

			txt += " %s remaining".printf(stat_time_remaining);

			return txt;
		}
	}
}

/*
Usage

*/
