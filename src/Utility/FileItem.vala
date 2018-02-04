/*
 * FileItem.vala
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

using GLib;
using Gtk;
using Gee;
using Json;

using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.JsonHelper;
using TeeJee.ProcessHelper;
using TeeJee.GtkHelper;
using TeeJee.System;
using TeeJee.Misc;

public class FileItem : GLib.Object, Gee.Comparable<FileItem> {

	public static Gee.HashMap<string, FileItem> cache = new Gee.HashMap<string, FileItem>();
	public static uint64 object_count = 0;

	public string file_path = ""; // disk path; can be empty for uri like network:///
	public string file_uri = "";  // uri; always non-empty
	public string file_uri_scheme = ""; // file, ftp, smb, etc
	//public string file_path_prefix = "";
	public FileType file_type = FileType.REGULAR;

	public DateTime modified = null;
	public DateTime accessed = null;
	public DateTime created = null;
	public DateTime changed = null;

	public string owner_user = "";
	public string owner_group = "";
	public string file_status = "";
	
	public string checksum_md5 = "";
	public string checksum_sha1 = "";   // sha1 - 160 bits
	public string checksum_sha256 = ""; // sha2 - 256 bits
	public string checksum_sha512 = ""; // sha2 - 512 bits
	
	public string checksum_compare = "";
	public ChecksumCompareResult checksum_compare_result;
	public string checksum_compare_message = "";
	public Gdk.Pixbuf checksum_compare_icon;
	
	public string content_type = "";
	public string content_type_desc = "";

	public uint32 unix_mode = 0;
	public string permissions = "";
	public string[] perms = {};

	public string edit_name = "";

	public bool can_read = false;
	public bool can_write = false;
	public bool can_execute = false;
	public bool can_rename = false;
	public bool can_trash = false;
	public bool can_delete = false;
	public bool permission_denied = false;
	public string access_flags = "";

	public uint64 filesystem_free = 0;
	public uint64 filesystem_size = 0;
	public uint64 filesystem_used = 0;
	public bool filesystem_read_only = false;
	public string filesystem_type = "";
	public string filesystem_id = "";
	
	// trash support ---------------------
	
	public bool is_trash = false;
	public bool is_trashed_item = false;

	public string trash_item_name = "";
	public string trash_info_file = "";
	public string trash_data_file = "";
	public string trash_basepath = "";
	public string trash_original_path = "";
	public uint32 trash_item_count = 0;
	public DateTime trash_deletion_date = null;

	// archive support ------------------------
	
	public static bool is_archive_by_extension(string fpath) {

		foreach(var ext in archive_extensions){
			if (fpath.has_suffix(ext)) {
				return true;
			}
		}

		return false;
	}

	public static bool is_package_by_extension(string fpath) {
	
		foreach(var ext in package_extensions){
			if (fpath.has_suffix(ext)) {
				return true;
			}
		}

		return false;
	}


	public static string[] archive_extensions = {
		".001", ".tar",
		".tar.gz", ".tgz",
		".tar.bzip2", ".tar.bz2", ".tbz", ".tbz2", ".tb2",
		".tar.lzma", ".tar.lz", ".tlz",
		".tar.xz", ".txz",
		".tar.7z",
		".tar.zip",
		".7z", ".lzma",
		".bz2", ".bzip2",
		".gz", ".gzip",
		".zip", ".rar", ".cab", ".arj", ".z", ".taz", ".cpio",
		".rpm", ".deb",
		".lzh", ".lha",
		".chm", ".chw", ".hxs",
		".iso", ".dmg", ".xar", ".hfs", ".ntfs", ".fat", ".vhd", ".mbr",
		".wim", ".swm", ".squashfs", ".cramfs", ".scap"
	};

	public static string[] package_extensions = {
		".rpm", ".deb"
	};

	// other -----------------
	
	public bool is_selected = false;
	public bool is_symlink = false;
	public bool is_symlink_broken = false;
	public string symlink_target = "";
	public bool is_stale = false;

	public bool fileinfo_queried{
		get{
			return (modified != null);
		}
	}

	//public bool attr_is_hidden = false;

	public FileItem parent;
	public Gee.HashMap<string, FileItem> children = new Gee.HashMap<string, FileItem>();

	public Gee.ArrayList<string> hidden_list = new Gee.ArrayList<string>();

	public GLib.Object? tag;
	//public Gtk.TreeIter? treeiter;
	public string compared_status = "";
	public string compared_file_path = "";

	//public long file_count = 0;
	//public long dir_count = 0;
	public long hidden_count = 0;
	public long file_count_total = 0;
	public long dir_count_total = 0;
	
	/*public long item_count{
		get {
			return (file_count + dir_count);
		}
	}*/

	public long item_count_total{
		get {
			return (file_count_total + dir_count_total);
		}
	}

	public bool children_queried = false; // if children have been added upto 1 level
	public bool query_children_running = false;
	public bool query_children_pending = false;
	protected Mutex mutex_children = Mutex();
	protected Mutex mutex_file_info = Mutex();
	
	// operation flags
	public bool query_children_follow_symlinks = true;
	public bool query_children_async_is_running = false;
	public bool query_children_aborted = false;

	public GLib.Icon icon;
	protected Gtk.Window? window = null;

	public bool is_dummy = false;

	private Gee.ArrayList<Gdk.Pixbuf> animation_list = new Gee.ArrayList<Gdk.Pixbuf>();

	// static  ------------------

	public static void init(){
		log_debug("FileItem: init()");
		cache = new Gee.HashMap<string, FileItem>();
	}

	// contructors -------------------------------

	public FileItem(string name = "New Archive") {
		//file_name = name;
	}

	public FileItem.dummy(FileType _file_type) {
		is_dummy = true;
		file_type = _file_type;
	}

	public FileItem.dummy_root() {
		//file_name = "dummy";
		//file_location = "";
		is_dummy = true;
	}

	public FileItem.from_path(string _file_path){
		// _file_path can be a local path, or GIO uri
		set_file_path(_file_path);
		query_file_info();
		object_count++;
	}

	public FileItem.from_path_and_type(string _file_path, FileType _file_type, bool query_info) {
		set_file_path(_file_path);
		file_type = _file_type;
		if (query_info){
			query_file_info();
		}
		object_count++;
	}

	public void set_file_path(string _file_path){

		GLib.File file;
		
		if (_file_path.contains("://")){
			file_uri = _file_path;
			file = File.new_for_uri(file_uri);
			file_path = file.get_path();
		}
		else {
			file_path = _file_path;
			file = File.new_for_path(file_path);
			file_uri = file.get_uri();
		}

		if (file_path == null){ file_path = ""; }

		file_uri_scheme = file.get_uri_scheme();
		
		//log_debug("");
		//log_debug("file_path      : %s".printf(file_path));
		//log_debug("file.get_path(): %s".printf(file.get_path()));
		//log_debug("file_uri       : %s".printf(file_uri));
		//log_debug("file_uri_scheme: %s".printf(file_uri_scheme));
	}

	public static void add_to_cache(FileItem item){
		
		cache[item.display_path] = item;
		
		if (item.is_directory){
			cache[item.display_path + "/"] = item;
		}
		
		//log_debug("add cache: %s".printf(item.display_path), true);
	}

	public static void remove_from_cache(FileItem item){
		
		if (cache.has_key(item.display_path)){
			cache.unset(item.display_path);
		}
		
		if (item.is_directory){
			if (cache.has_key(item.display_path + "/")){
				cache.unset(item.display_path + "/");
			}
		}
		
		//log_debug("add cache: %s".printf(item.display_path), true);
	}

	public static FileItem? find_in_cache(string item_display_path){

		if (cache.has_key(item_display_path)){
			var cached_item = cache[item_display_path];
			//if (!cached_item.is_directory){
				//log_debug("get cache: %s".printf(item_display_path), true);
				return cached_item;
			//}
		}

		return null;
	}
	
	// size and count ---------------

	public bool dir_size_queried = false;
	
	protected int64 _file_size = 0;
	
	public int64 file_size {
		get{
			return _file_size;
		}
		set{
			_file_size = value;
			if (is_directory){
				dir_size_queried = true;
			}
		}
	}

	public int64 get_dir_size_recursively(bool depth_is_negative){
		
		int64 dir_size = 0;

		foreach(var child in children.values){
			if (child.is_directory){
				if (child.dir_size_queried){
					dir_size += child.file_size;
				}
				else{
					dir_size += child.get_dir_size_recursively(depth_is_negative);
				}
			}
			else{
				dir_size += child.file_size;
			}
		}

		if (depth_is_negative){
			file_size = dir_size;
			dir_size_queried = true;
		}
		
		return dir_size;
	}

	public long get_file_count_recursively(bool depth_is_negative){
		
		long count = 0;

		foreach(var child in children.values){
			if (child.is_directory){
				count += child.get_file_count_recursively(depth_is_negative);
			}
			else{
				count += 1;
			}
		}

		if (depth_is_negative){
			file_count_total = count;
		}

		return count;
	}

	public long get_dir_count_recursively(bool depth_is_negative){
		
		long count = 0;

		foreach(var child in children.values){
			if (child.is_directory){
				count += 1;
				count += child.get_dir_count_recursively(depth_is_negative);
			}
		}

		if (depth_is_negative){
			dir_count_total = count;
		}

		return count;
	}

	public int64 item_count = 0;

	public int64 file_count = 0;
	
	public int64 dir_count = 0;

	public int64 size_compressed = 0;

	public string file_size_formatted {
		owned get{

			string txt = "";
			
			if (is_dummy) {
				txt += "-";
			}
			else if (is_directory){
				
				if (dir_size_queried){
					if (file_size > 0){
						txt += format_file_size(file_size);
					}
					else{
						txt += _("empty");
					}
				}
				else if (query_children_running){
					txt += "...";
				}
				else if (query_children_pending){
					txt += "";
				}
				else if (children_queried){
					
					if (item_count == 1){
						txt += "%'lld %s".printf(item_count, _("item"));
					}
					else if (item_count > 1){
						txt += "%'lld %s".printf(item_count, _("items"));
					}
					else{ //(item_count == 0){
						txt += _("empty");
					}
				}
				else{
					txt += format_file_size(file_size);
				}
			}
			else {
				txt += format_file_size(file_size);
			}

			return txt;
		}
	}

	public bool exists_on_disk() {

		GLib.File file;
		
		if (file_path.length > 0){
			file = File.new_for_path(file_path);
		}
		else{
			file = File.new_for_uri(file_uri);
		}

		return file.query_exists();
	}

	// name and path -----------------------

	public string file_name {
		owned get{
			if (file_path.length == 0){ return ""; }
			return file_basename(file_path);
		}
	}

	public string file_extension {
		owned get{
			return file_get_extension(file_path);
		}
	}
	
	public string file_title {
		owned get{
			if (file_path.length == 0){ return ""; }
			int end = file_name.length - file_extension.length;
			return file_name[0:end];
		}
	}

	public string file_location {
		owned get{
			if (file_path.length == 0){ return ""; }
			return file_parent(file_path);
		}
	}

	protected string _thumb_key = null;
	public string thumb_key {
		get {
			if (_thumb_key == null){
				_thumb_key = string_checksum(file_uri);
			}
			return _thumb_key;
		}
	}

	protected string _display_name = null;
	public string display_name {
		owned get {
			if (_display_name != null){
				return _display_name;
			}
			else if (is_trashed_item){
				return file_basename(display_path);
			}
			else{
				return file_basename(file_path);
			}
		}
		set {
			_display_name = value;
		}
	}

	protected string _display_path = "";
	public virtual string display_path {
		owned get {

			if (_display_path.length > 0){ 
				return _display_path;
			}
			
			string txt = "";

			if (is_trash){
				txt = "trash:///";
			}
			else if ((file_path != null) && (file_path.length > 0)){
				txt = file_path;
			}
			else{
				txt = file_uri;
			}

			return txt;
		}
		set {
			_display_path = value;
		}
	}

	public string display_location {
		owned get{
			return file_parent(display_path);
		}
	}

	// helpers ---------------------
	
	public bool is_backup {
		get{
			return file_name.has_suffix("~");
		}
	}

	public bool is_hidden {
		get{
			return file_name.has_prefix(".") || ((parent != null) && parent.hidden_list.contains(file_name));
		}
	}

	public bool is_backup_or_hidden {
		get{
			return is_backup || is_hidden;
		}
	}

	public bool is_directory {
		get{
			return (file_type == FileType.DIRECTORY);
		}
	}

	public bool is_local {
		get{
			return (file_uri_scheme == "file");
		}
	}

	public bool is_remote {
		get{
			switch(file_uri_scheme){
			case "ftp":
			case "sftp":
			case "ssh":
			case "smb":
			case "mtp":
				return true;
			default:
				return false;
			}
		}
	}

	public bool is_sys_root {
		get{
			return children.has_key("bin")
				&& children.has_key("dev")
				&& children.has_key("proc")
				&& children.has_key("run")
				&& children.has_key("sys");
		}
	}

	public bool has_child(string base_name) {
		return this.children.keys.contains(base_name);
	}

	private string get_access_flags() {
		string txt = "";
		txt += can_read ? "R" : "-";
		txt += can_write ? "W" : "-";
		txt += can_execute ? "X" : "-";
		txt += can_rename ? "N" : "-";
		txt += can_trash ? "T" : "-";
		txt += can_delete ? "D" : "-";
		return txt;
	}

	public string file_name_ellipsized {
		owned get{
			int max_chars = 20;
			return (file_name.length) > max_chars ? file_name[0:max_chars-1] + "..." : file_name;
		}
	}

	public string display_name_ellipsized {
		owned get{
			int max_chars = 20;
			return (display_name.length > max_chars) ? display_name[0:max_chars-1] + "..." : display_name;
		}
	}

	public string tile_tooltip {
		owned get{
			string txt = "";
			txt += "%s:  %s\n".printf(_("Name"), escape_html(file_name));
			txt += "%s:  %s\n".printf(_("Size"), file_size_formatted);
			if (modified != null){
				txt += "%s:  %s\n".printf(_("Modified"), modified.format("%Y-%m-%d %H:%M"));
			}
			txt += "%s:  %s\n".printf(_("Type"), escape_html(content_type_desc));
			txt += "%s:  %s".printf(_("Mime"), content_type);
			return txt;
		}
	}

	public string tile_markup {
		owned get{
			return "%s\n<i>%s</i>\n<i>%s</i>".printf(display_name_ellipsized, file_size_formatted, content_type_desc);
		}
	}

	public string modified_formatted{
		owned get {
			if (modified != null) {
				return modified.format ("%Y-%m-%d %H:%M");
			}
			else {
				return "(empty)";
			}
		}
	}

	public int64 modified_unix_time{
		get {
			int64 time = 0;
			if (modified != null){
				time = modified.to_unix();
			}
			return time;
		}
	}

	// check file type ----------------------
	
	public bool is_image{
		get{
			return content_type.has_prefix("image/");
		}
	}

	public bool is_text{
		get{
			return content_type.has_prefix("text/");
		}
	}

	public bool is_audio{
		get{
			return content_type.has_prefix("audio/");
		}
	}

	public bool is_video{
		get{
			return content_type.has_prefix("video/");
		}
	}

	public bool is_pdf{
		get{
			return file_extension.down().has_suffix(".pdf")
				|| (content_type == "application/pdf")
				|| (content_type == "application/x-pdf");
		}
	}

	public bool is_png{
		get{
			return file_extension.down().has_suffix(".png")
				|| (content_type == "image/png");
		}
	}

	public bool is_jpeg{
		get{
			return file_extension.down().has_suffix(".jpeg")
				|| file_extension.down().has_suffix(".jpg")
				|| (content_type == "image/jpeg");
		}
	}

	public bool is_gif{
		get{
			return file_extension.down().has_suffix(".gif")
				|| (content_type == "image/gif");
		}
	}

	public bool is_iso{
		get{
			return file_extension.down().has_suffix(".iso")
				|| (content_type == "application/iso-image")
				|| (content_type == "application/x-iso-image");
		}
	}

	public bool is_squashfs {
		get {
			return file_extension.down().has_suffix(".sfs")
				|| file_extension.down().has_suffix(".squashfs")
				|| (content_type == "application/vnd.squashfs");
		}
	}

	public bool is_img {
		get {
			return file_extension.down().has_suffix(".img")
				|| (content_type == "application/x-raw-disk-image");
		}
	}

	public bool is_disk_image{
		get{
			return is_iso || is_squashfs || is_img;
		}
	}

	public bool is_file_hash{
		get{
			return file_extension.down().has_suffix(".md5")
			|| file_extension.down().has_suffix(".sha1")
			|| file_extension.down().has_suffix(".sha2")
			|| file_extension.down().has_suffix(".sha256")
			|| file_extension.down().has_suffix(".sha512");
		}
	}

	public bool is_media_directory{
		get{
			int media_count = count_photos + count_videos;
			if (media_count == 0){ return false; }
			return (media_count >= (file_count / 2)) || (media_count >= 4);
		}
	}

	public int count_photos {
		get{
			int count = 0;
			foreach(var child in children.values){
				if (child.is_image){ count++; }
			}
			return count;
		}
	}

	public int count_documents {
		get{

			int count = 0;

			foreach(var child in children.values){

				switch(child.file_extension.down()){
				case "doc":
				case "docx":
				case "xls":
				case "xlsx":
				case "ppt":
				case "pptx":
				case "pdf":
				case "odt":
				case "ods":
				case "odp":
				case "epub":
				case "rtf":
					count++;
					break;
				}
			}

			return count;
		}
	}

	public int count_music {
		get{
			int count = 0;
			foreach(var child in children.values){
				if (child.is_audio){ count++; }
			}
			return count;
		}
	}

	public int count_videos {
		get{
			int count = 0;
			foreach(var child in children.values){
				if (child.is_video){ count++; }
			}
			return count;
		}
	}

	// icons ----------------------------------------------

	public Gdk.Pixbuf? get_image(int icon_size,
		bool load_thumbnail, bool add_transparency, bool add_emblems, out ThumbTask? task){

		Gdk.Pixbuf? pixbuf = null;
		
		task = null;

		//if (changed == null){
			//log_trace("changed=NULL: %s".printf(display_path));
		//}

		Gdk.Pixbuf? cached = IconCache.lookup_icon_fileitem(
			display_path, changed, icon_size,
			load_thumbnail, add_transparency, add_emblems); // TODO: use file_path_uri

		if (cached != null){
			return cached;
		}

		if (load_thumbnail && !is_directory){
			pixbuf = get_thumbnail(icon_size, add_transparency, add_emblems, out task);
		}
		else{
			pixbuf = get_icon(icon_size, add_transparency, add_emblems);
		}

		if (task == null){
			IconCache.add_icon_fileitem(pixbuf, display_path, changed, icon_size, // TODO: use file_path_uri
				load_thumbnail, add_transparency, add_emblems);
		}

		return pixbuf;
	}

	public Gdk.Pixbuf? get_icon(int icon_size, bool add_transparency, bool add_emblems){

		Gdk.Pixbuf? pixbuf = null;

		if (icon != null) {
			pixbuf = IconManager.lookup_gicon(icon, icon_size);
		}

		if (pixbuf == null){
			if (file_type == FileType.DIRECTORY) {
				pixbuf = IconManager.lookup("folder", icon_size, false);
			}
			else{
				pixbuf = IconManager.lookup("text-x-preview", icon_size, false);
			}
		}

		if (pixbuf == null){ return null; }

		if (add_emblems){
			pixbuf = add_emblems_for_state(pixbuf, false);
		}

		if (add_transparency && is_backup_or_hidden){
			pixbuf = IconManager.add_transparency(pixbuf);
		}

		return pixbuf;
	}

	public Gdk.Pixbuf? get_thumbnail(int icon_size, bool add_transparency, bool add_emblems, out ThumbTask? task){

		Gdk.Pixbuf? pixbuf = Thumbnailer.lookup(this, icon_size);

		//log_debug("get_thumbnail: %s".printf(file_path));
		// TODO2: Thumbnailer should create fail image (icon)
		// TODO2: get rid of thumbtask
		if ((pixbuf == null) && !is_directory && (is_image || is_video)){
			//log_debug("get_thumbnail: add_task: %s".printf(file_path));
			task = new ThumbTask(this, icon_size);
			Thumbnailer.add_to_queue(task);
		}
		else{
			task = null;
		}

		if (pixbuf == null){
			pixbuf = get_icon(icon_size, false, false);
		}

		if (pixbuf == null){ return null; }

		if (add_emblems){
			pixbuf = add_emblems_for_state(pixbuf, false);
		}

		if (add_transparency && is_backup_or_hidden){
			pixbuf = IconManager.add_transparency(pixbuf);
		}

		return pixbuf;
	}

	public Gee.ArrayList<Gdk.Pixbuf> get_animation(int icon_size){

		if (animation_list == null){
			animation_list = new Gee.ArrayList<Gdk.Pixbuf>();
		}

		if (animation_list.size > 0){
			return animation_list;
		}

		animation_list = Thumbnailer.lookup_animation(this, icon_size);
		return animation_list;
	}

	public Gdk.Pixbuf? add_emblems_for_state(Gdk.Pixbuf pixbuf, bool emblem_symbolic){

		int width = pixbuf.get_width();
		int height = pixbuf.get_height();

		int icon_size = (width > height) ? width : height;

		//if (icon_size < 32){
		//	return pixbuf; // icon is too small for emblems to be drawn over it
		//}

		//int emblem_size = (int) (icon_size * 0.40);

		int emblem_size = 16;
		
		if (icon_size < 32){
			emblem_size = 8;
		}

		Gdk.Pixbuf? emblemed = pixbuf.copy();

		if (is_symlink){
			emblemed = IconManager.add_emblem(emblemed, "emblem-symbolic-link", emblem_size, emblem_symbolic, Gtk.CornerType.BOTTOM_RIGHT);
		}

		if (!can_write){
			emblemed = IconManager.add_emblem(emblemed, "emblem-readonly", emblem_size, emblem_symbolic, Gtk.CornerType.TOP_RIGHT);
		}

		if (is_directory && (icon_size >= 32)){

			if (icon_size >= 32){
				emblem_size = (int) (icon_size * 0.40);
			}

			if (count_documents > 0){
				emblemed = IconManager.add_emblem(emblemed, "emblem-documents", emblem_size, emblem_symbolic, Gtk.CornerType.BOTTOM_LEFT);
			}
			else if (count_photos > 0){
				emblemed = IconManager.add_emblem(emblemed, "emblem-photos", emblem_size, emblem_symbolic, Gtk.CornerType.BOTTOM_LEFT);
			}
			else if (count_music > 0){
				emblemed = IconManager.add_emblem(emblemed, "emblem-music", emblem_size, emblem_symbolic, Gtk.CornerType.BOTTOM_LEFT);
			}
			else if (count_videos > 0){
				emblemed = IconManager.add_emblem(emblemed, "emblem-videos", emblem_size, emblem_symbolic, Gtk.CornerType.BOTTOM_LEFT);
			}
		}

		return emblemed;
	}

	public Gtk.Image? get_icon_image(int icon_size, bool add_transparency, bool add_emblems){
		
		Gdk.Pixbuf? pix = get_icon(icon_size, add_transparency, add_emblems);
		
		if (pix != null){
			return new Gtk.Image.from_pixbuf(pix);
		}
		else{
			return null;
		}
	}
	
	// helpers ----------------------------------------------

	public int compare_to(FileItem b){

		if (this.file_type == b.file_type) {
			return strcmp(this.file_name.down(), b.file_name.down());
		}
		else{
			if (this.file_type == FileType.DIRECTORY) {
				return -1;
			}
			else {
				return +1;
			}
		}
	}

	public string resolve_symlink_target(){

		string target_path = file_parent(file_path); // remove symlink file name

		foreach(var part in symlink_target.split("/")){
			if (part == ".."){
				target_path = file_parent(target_path);
			}
			else if (part == "."){
				// no change
			}
			else if (part.length == 0){
				target_path = "/";
			}
			else{
				target_path = path_combine(target_path, part);
			}
		}

		return target_path;
	}

	public Device? get_device(){
		return Device.get_device_for_path(file_path);
	}
	
	// query info --------------------------

	public virtual void query_file_info() {

		try {

			//var timer = timer_start();
			
			//log_debug("query_file_info(): %s".printf(file_path));

			FileInfo info;
			GLib.File file;
			
			if (file_path.length > 0){
				file = File.new_for_path(file_path);
			}
			else{
				file = File.new_for_uri(file_uri);
			}

			if (!file.query_exists()) {
				log_debug("query_file_info(): not found: %s".printf(file_path));
				return;
			}

			mutex_file_info.lock();
			
			// get type without following symlinks

			info = file.query_info("%s,%s,%s".printf(
									   FileAttribute.STANDARD_TYPE,
									   FileAttribute.STANDARD_ICON,
									   FileAttribute.STANDARD_SYMLINK_TARGET),
									   FileQueryInfoFlags.NOFOLLOW_SYMLINKS);

			var item_file_type = info.get_file_type();

			if (item_file_type == FileType.SYMBOLIC_LINK) {
				//this.icon = GLib.Icon.new_for_string("emblem-symbolic-link");
				this.is_symlink = true;
				this.symlink_target = info.get_symlink_target();
			}
			else {
				this.is_symlink = false;
				this.symlink_target = "";
			}

			this.icon = info.get_icon();

			//NOTE: permissions of symbolic links are never used

			//log_trace("query_info: %s".printf(timer_elapsed_string(timer)));
			//timer_restart(timer);

			// get file info by follow symlinks ---------------------------------------

			info = file.query_info("%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s".printf(
									   FileAttribute.STANDARD_TYPE,
									   FileAttribute.STANDARD_SIZE,
									   FileAttribute.STANDARD_ICON,
									   FileAttribute.STANDARD_CONTENT_TYPE,
									   FileAttribute.STANDARD_DISPLAY_NAME,
									   FileAttribute.STANDARD_EDIT_NAME,
									   FileAttribute.TIME_CREATED,
									   FileAttribute.TIME_ACCESS,
									   FileAttribute.TIME_MODIFIED,
									   FileAttribute.TIME_CHANGED,
									   FileAttribute.OWNER_USER,
									   FileAttribute.OWNER_GROUP,
									   FileAttribute.FILESYSTEM_FREE,
									   FileAttribute.ACCESS_CAN_DELETE,
									   FileAttribute.ACCESS_CAN_EXECUTE,
									   FileAttribute.ACCESS_CAN_READ,
									   FileAttribute.ACCESS_CAN_RENAME,
									   FileAttribute.ACCESS_CAN_TRASH,
									   FileAttribute.ACCESS_CAN_WRITE,
									   FileAttribute.UNIX_MODE,
									   FileAttribute.ID_FILESYSTEM//,
									   //FileAttribute.GVFS_BACKEND
									   ), 0);

			//log_trace("query_info: %s".printf(timer_elapsed_string(timer)));

			// file type resolved
			this.file_type = info.get_file_type();

			//log_debug("resolved_type: %s, %s".printf(file_name, file_type.to_string()));

			if (file_type == FileType.SYMBOLIC_LINK){
				this.is_symlink_broken = true;
				this.file_type = FileType.REGULAR; // fake it, so that sorting is not broken
				//log_debug("broken_link: %s".printf(file_name));
			}
			
			if (this.is_symlink && !this.is_symlink_broken){
				// get icon for the resolved file
				this.icon = info.get_icon();
			}

			// content type
			this.content_type = info.get_content_type();

			// size
			this._file_size = info.get_size();

			// modified
			this.modified = (new DateTime.from_timeval_utc(info.get_modification_time())).to_local();

			if (info.has_attribute(FileAttribute.TIME_ACCESS)){
				var time = (int64) info.get_attribute_uint64(FileAttribute.TIME_ACCESS); // convert uint64 to int64
				this.accessed = (new DateTime.from_unix_utc(time)).to_local();
			}

			if (info.has_attribute(FileAttribute.TIME_CREATED)){
				var time = (int64) info.get_attribute_uint64(FileAttribute.TIME_CREATED); // convert uint64 to int64
				this.created = (new DateTime.from_unix_utc(time)).to_local();
			}

			if (info.has_attribute(FileAttribute.TIME_CHANGED)){
				var time = (int64) info.get_attribute_uint64(FileAttribute.TIME_CHANGED); // convert uint64 to int64
				this.changed = (new DateTime.from_unix_utc(time)).to_local();
			}

			// owner_user
			this.owner_user = info.get_attribute_string(FileAttribute.OWNER_USER);
			if (owner_user == null) { owner_user = ""; }
			
			// owner_group
			this.owner_group = info.get_attribute_string(FileAttribute.OWNER_GROUP);
			if (owner_group == null) { owner_group = ""; }
			
			this.can_read = info.get_attribute_boolean(FileAttribute.ACCESS_CAN_READ);
			this.can_write = info.get_attribute_boolean(FileAttribute.ACCESS_CAN_WRITE);
			this.can_execute = info.get_attribute_boolean(FileAttribute.ACCESS_CAN_EXECUTE);

			this.can_rename = info.get_attribute_boolean(FileAttribute.ACCESS_CAN_RENAME);
			this.can_trash = info.get_attribute_boolean(FileAttribute.ACCESS_CAN_TRASH);
			this.can_delete = info.get_attribute_boolean(FileAttribute.ACCESS_CAN_DELETE);

			this.access_flags = get_access_flags();

			//this.attr_is_hidden = info.get_is_hidden();

			if (info.has_attribute(FileAttribute.UNIX_MODE)){
				this.unix_mode = info.get_attribute_uint32(FileAttribute.UNIX_MODE);
				parse_permissions();
			}

			this.filesystem_id = info.get_attribute_string(FileAttribute.ID_FILESYSTEM);

			if (this.file_type == FileType.DIRECTORY){
				query_file_system_info();
				read_hidden_list();
			}

			set_content_type_desc();
		}
		catch (Error e) {
			log_error (e.message);
		}

		mutex_file_info.unlock();
	}

	public virtual void query_children(int depth, bool follow_symlinks) {

		//log_debug("FileItem: query_children(): enter");
		
		/* Queries the file item's children using the file_path
		 * depth = -1, recursively find and add all children from disk
		 * depth =  1, find and add direct children
		 * depth =  0, meaningless, should not be used
		 * depth =  X, find and add children upto X levels
		 * */

		if (query_children_aborted) { return; }

		if (query_children_running) { return; }

		// check if directory and continue -------------------
		
		if (!is_directory) {
			query_file_info();
			query_children_running = false;
			query_children_pending = false;
			log_debug("FileItem: query_children(): FileType != DIRECTORY");
			return;
		}

		if (depth == 0){ return; } // incorrect method call

		log_debug("FileItem: query_children(%d): %s".printf(depth, file_path), true);

		query_children_running = true;
		
		query_children_follow_symlinks = follow_symlinks;

		FileEnumerator enumerator;
		FileInfo info;
		GLib.File file;

		if (file_path.length > 0){
			file = File.new_for_path(file_path);
		}
		else{
			file = File.new_for_uri(file_uri);
		}

		if (!file.query_exists()) {
			log_error("FileItem: query_children(): file not found: %s".printf(file_path));
			query_children_running = false;
			query_children_pending = false;
			return;
		}

		//mutex_children.lock();
		//log_debug("FileItem: query_children(): lock_acquired");
		
		query_file_info(); // read folder properties
		
		try{

			if (depth < 0){
				dir_size_queried = false;
			}

			permission_denied = false;
			
			// mark existing children as stale -----------------
			
			foreach(var child in children.values){
				child.is_stale = true;
			}

			// reset counts --------------
			
			item_count = 0;
			file_count = 0;
			dir_count = 0;

			//log_debug("FileItem: query_children(): enumerate_children");

			// recurse children -----------------------
			
			enumerator = file.enumerate_children ("%s".printf(FileAttribute.STANDARD_NAME), 0);
			while ((info = enumerator.next_file()) != null) {
				//log_debug("FileItem: query_children(): found: %s".printf(info.get_name()));
				string child_name = info.get_name();
				string child_path = GLib.Path.build_filename(file_path, child_name);
				//log_debug("FileItem: query_children(): child_path: %s".printf(child_path));
				var child = this.add_child_from_disk(child_path, depth - 1);
				//child.is_stale = false;
				//log_debug("fresh: name: %s".printf(child.file_name));
				//if (query_children_aborted) { break; }
			}

			//log_debug("FileItem: query_children(): enumerate_children: done");

			// update counts --------------------------
			
			foreach(var child in children.values){
				if (child.is_directory){
					dir_count++;
				}
				else{
					file_count++;
				}
				item_count++;
			}
			children_queried = true;

			//log_debug("FileItem: query_children(): count_children: done");

			// remove stale children ----------------------------
			
			var list = new Gee.ArrayList<string>();
			foreach(var key in children.keys){
				if (children[key].is_stale){
					list.add(key);
				}
			}
			foreach(var key in list){
				//log_debug("unset: key: %s, name: %s".printf(key, children[key].file_name));
				children.unset(key);
			}

			//log_debug("FileItem: query_children(): remove_stale_children: done");

			if (depth < 0){
				get_dir_size_recursively(true);
			}
		}
		catch (Error e) {
			log_error (e.message);
			permission_denied = true;
		}

		//add_to_cache(this);

		query_children_running = false;
		query_children_pending = false;

		//mutex_children.unlock();
		//log_debug("FileItem: query_children(): lock_released");
	}

	public virtual void query_children_async(bool follow_symlinks) {

		log_debug("query_children_async(): %s".printf(file_path));

		query_children_follow_symlinks = follow_symlinks;
		
		query_children_async_is_running = true;
		query_children_aborted = false;

		try {
			//start thread
			Thread.create<void> (query_children_async_thread, true);
		}
		catch (Error e) {
			log_error ("FileItem: query_children_async(): error");
			log_error (e.message);
		}
	}

	private void query_children_async_thread() {
		log_debug("query_children_async_thread()");
		query_children(-1, query_children_follow_symlinks); // always add to cache
		query_children_async_is_running = false;
		query_children_aborted = false; // reset
	}
	
	public virtual void query_file_system_info(bool fix_fstype = false) {

		try {
			var file = File.parse_name(file_path);

			var info = file.query_filesystem_info("%s,%s,%s,%s,%s".printf(
											   FileAttribute.FILESYSTEM_FREE,
											   FileAttribute.FILESYSTEM_SIZE,
											   FileAttribute.FILESYSTEM_USED,
											   FileAttribute.FILESYSTEM_READONLY,
											   FileAttribute.FILESYSTEM_TYPE
											   ), null);

			this.filesystem_free = info.get_attribute_uint64(FileAttribute.FILESYSTEM_FREE);
			this.filesystem_size = info.get_attribute_uint64(FileAttribute.FILESYSTEM_SIZE);
			this.filesystem_used = info.get_attribute_uint64(FileAttribute.FILESYSTEM_USED);
			this.filesystem_read_only = info.get_attribute_boolean(FileAttribute.FILESYSTEM_READONLY);
			this.filesystem_type = info.get_attribute_string(FileAttribute.FILESYSTEM_TYPE);
			//this.filesystem_type = (this.filesystem_type == "ext3/ext4") ? "ext3/4" : this.filesystem_type;
		}
		catch (Error e) {
			log_error (e.message);
		}
	}

	public void read_hidden_list(){

		hidden_list = new Gee.ArrayList<string>();

		if (is_remote){ return; }

		string hidden_file = path_combine(file_path, ".hidden");

		if (file_exists(hidden_file)){

			foreach(string line in file_read(hidden_file).split("\n")){
				if (line.contains("/")){
					hidden_list.add(file_basename(line));
				}
				else{
					hidden_list.add(line);
				}
			}
		}
	}

	public void clear_children() {
		this.children.clear();
	}

	public FileItem? find_descendant(string path){
		var child = this;

		foreach(var part in path.split("/")){

			// query children if needed
			if (child.children.size == 0){
				if (child.is_directory){
					child.query_children(1, true);
				}
				else{
					break;
				}
				if (child.children.size == 0){
					break;
				}
			}

			if (child.children.has_key(part)){
				child = child.children[part];
			}
		}

		if (child.file_path == path){
			return child;
		}
		else{
			return null;
		}
	}

	public void print(int level) {

		if (level == 0) {
			stdout.printf("\n");
			stdout.flush();
		}

		stdout.printf("%s%s\n".printf(string.nfill(level * 2, ' '), file_name));
		stdout.flush();

		foreach (var key in this.children.keys) {
			this.children[key].print(level + 1);
		}
	}

	public Gee.ArrayList<FileItem> get_children_sorted(){
		var list = new Gee.ArrayList<FileItem>();

		foreach(string key in children.keys) {
			var item = children[key];
			list.add(item);
		}

		list.sort((a, b) => {
			if (a.is_directory && !b.is_directory){
				return -1;
			}
			else if (!a.is_directory && b.is_directory){
				return 1;
			}
			else{
				return strcmp(a.file_name.down(), b.file_name.down());
			}
		});

		return list;
	}

	// instance methods ------------------------------------------

	public FileItem? add_child_from_disk(string child_item_file_path, int depth = -1) {

		/* Adds specified item on disk to current FileItem
		 * Adds the item's children recursively if depth is -1 or > 0
		 *  depth =  0, add child item, count child item's children if directory
		 *  depth = -1, add child item, add child item's children from disk recursively
		 *  depth =  X, add child item, add child item's children upto X levels
		 * */

		if (query_children_aborted){ return null; }

		FileItem item = null;

		//log_debug("add_child_from_disk(): %s".printf(child_item_file_path));

		try {
			FileEnumerator enumerator;
			FileInfo info;
			File file = File.parse_name(child_item_file_path);

			if (!file.query_exists()) { return null; }

			// query file type
			var item_file_type = file.query_file_type(FileQueryInfoFlags.NONE);

			// add item
			item = this.add_child(child_item_file_path, item_file_type, 0, 0, true);
			
			// check if directory  ---------------------------------
			
			if (!item.is_directory) { return item; }

			if (!item.can_read){ return item; }

			if (depth == 0){ return item; }

			if (!query_children_follow_symlinks && item.is_symlink) { return item; }
			
			//log_debug("add_child_from_disk(): enumerate_children");

			// enumerate item's children ----------------------------
			
			enumerator = file.enumerate_children ("%s,%s".printf(FileAttribute.STANDARD_NAME,FileAttribute.STANDARD_TYPE), 0);
			
			while ((info = enumerator.next_file()) != null) {

				try {
					if (query_children_aborted) {
						item.query_children_aborted = true;
						//item.dir_size_queried = false;
						return null;
					}
					
					string child_path = path_combine(child_item_file_path, info.get_name());
		
					if (depth != 0){
						// add item's children from disk and drill down further
						item.add_child_from_disk(child_path, depth - 1);
					}
				}
				catch(Error e) {
					log_error (e.message);
				}
			}

		}
		catch (Error e) {
			log_error (e.message);
		}

		return item;
	}

	public FileItem add_descendant(string _file_path, FileType? _file_type, int64 item_size,int64 item_size_compressed) {
		
		FileItem? item = null;
			
		//log_debug("FileItem: add_descendant=%s".printf(_file_path));

		string item_path = _file_path.strip();
		FileType item_type = (_file_type == null) ? FileType.REGULAR : _file_type;

		if (item_path.has_suffix("/")) {
			item_path = item_path[0:item_path.length - 1];
			item_type = FileType.DIRECTORY;
		}

		if (item_path.has_prefix("/")) {
			item_path = item_path[1:item_path.length];
		}

		string dir_name = "";
		string dir_path = "";

		// create dirs and find parent dir
		FileItem current_dir = this;
		
		string[] arr = item_path.split("/");

		//mutex_children.lock();
		
		for (int i = 0; i < arr.length - 1; i++) {
			
			//get dir name
			dir_name = arr[i];

			//add dir
			if (!current_dir.children.keys.contains(dir_name)) {
				if ((current_dir == this) && (current_dir is FileItemArchive)){
					dir_path = "";
				}
				else {
					dir_path = current_dir.file_path + "/";
				}
				dir_path = "%s%s".printf(dir_path, dir_name);
				current_dir.add_child(dir_path, FileType.DIRECTORY, 0, 0, false);
			}

			current_dir = current_dir.children[dir_name];
		}

		//mutex_children.unlock();

		string item_name = arr[arr.length - 1];

		if (current_dir.children.keys.contains(item_name)) {

			item = current_dir.children[item_name];
		}
		else{
			log_debug("add_descendant: add_child()");
			item = current_dir.add_child(item_path, item_type, item_size, item_size_compressed, false);
		}

		log_debug("add_descendant: finished: %s".printf(item_path));

		return item;
	}

	public virtual FileItem add_child(string item_file_path, FileType item_file_type,
		int64 item_size, int64 item_size_compressed, bool item_query_file_info){

		// create new item ------------------------------

		//log_debug("FileItem: add_child: %s ---------------".printf(item_file_path));

		mutex_children.lock();
		
		FileItem item = null;

		// check existing ----------------------------

		bool existing_file = false;

		string item_name = file_basename(item_file_path);
		
		if (children.has_key(item_name) && (children[item_name].file_name == item_name)){

			existing_file = true;
			item = children[item_name];
			item.set_file_path(item_file_path); // path may have changed (rename issue)
			
			//log_debug("existing child, queried: %s".printf(item.fileinfo_queried.to_string()));
		}
		/*else if (cache.has_key(item_file_path) && (cache[item_file_path].file_path == item_file_path)){
			
			item = cache[item_file_path];

			// set relationships
			item.parent = this;
			this.children[item.file_name] = item;

			//log_debug("cached child");
		}*/
		else{

			if (item == null){
				item = new FileItem.from_path_and_type(item_file_path, item_file_type, false);
			}
			
			// set relationships
			item.parent = this;
			this.children[item.file_name] = item;

			//log_debug("new child");
		}

		item.is_stale = false; // mark fresh

		//item.display_path = path_combine(this.display_path, item_name);

		//bool item_was_queried = item.fileinfo_queried;
		
		// query file properties ------------
		
		if (item_query_file_info){
			item.query_file_info();
		}

		if (item_file_type == FileType.REGULAR) {

			//log_debug("add_child: regular file");

			// update item size -----------------------------------

			if (!item_query_file_info){
				item.file_size = item_size;
			}

			// update hidden count -------------------------

			if (!existing_file){
				if (item.is_backup_or_hidden){
					this.hidden_count++;
				}
			}
		}
		else if (item_file_type == FileType.DIRECTORY) {

			//log_debug("add_child: directory");
		}

		mutex_children.unlock();

		return item;
	}

	public FileItem remove_child(string child_name) {
		FileItem child = null;

		if (this.children.has_key(child_name)) {
			child = this.children[child_name];
			this.children.unset(child_name);

			if (child.file_type == FileType.REGULAR) {
				/*
				//update file counts
				this.file_count--;
				this.file_count_total--;
				*/
				
				//subtract child size
				//this._size -= child.size;
				//this._size_compressed -= child.size_compressed;

				//update file count and size of parent dirs
				var temp = this;
				while (temp.parent != null) {
					temp.parent.file_count_total--;

					//temp.parent._size -= child.size;
					//temp.parent._size_compressed -= child.size_compressed;

					temp = temp.parent;
				}
			}
			else {
				/*
				//update dir counts
				this.dir_count--;
				this.dir_count_total--;
				*/
				
				//subtract child counts
				this.file_count_total -= child.file_count_total;
				this.dir_count_total -= child.dir_count_total;
				//this._size -= child.size;
				//this._size_compressed -= child.size_compressed;

				//update dir count of parent dirs
				var temp = this;
				while (temp.parent != null) {
					temp.parent.dir_count_total--;

					temp.parent.file_count_total -= child.file_count_total;
					temp.parent.dir_count_total -= child.dir_count_total;
					//temp.parent._size -= child.size;
					//temp.parent._size_compressed -= child.size_compressed;

					temp = temp.parent;
				}
			}
		}

		//log_debug("%3ld %3ld %s".printf(file_count, dir_count, file_path));

		return child;
	}

	public FileItem rename_child(string child_name, string new_name){

		log_debug("FileItem: rename_child(): %s -> %s".printf(child_name, new_name));

		FileItem child = null;

		if (this.children.has_key(child_name)) {

			child = this.children[child_name];

			// unset
			this.children.unset(child_name);
			remove_from_cache(child);

			// set
			this.children[new_name] = child;
			child.file_path = path_combine(child.file_location, new_name);
			child.display_name = null;
			child.query_file_info();
			//add_to_cache(child);
		}

		return child;
	}

	public bool hide_item(){

		if ((parent != null) && dir_exists(parent.file_path)){

			string hidden_file = path_combine(parent.file_path, ".hidden");
			string txt = "";

			if (file_exists(hidden_file)){
				txt = file_read(hidden_file);
			}

			txt += (txt.length == 0) ? "" : "\n";
			txt += "%s".printf(file_name);

			file_write(hidden_file, txt, null, null, true); // overwrite in-place
			parent.read_hidden_list();
			update_access_time();
			return true;
		}

		return false;
	}

	public bool unhide_item(){

		if ((parent != null) && dir_exists(parent.file_path)){

			string hidden_file = path_combine(parent.file_path, ".hidden");
			string txt = "";

			if (file_exists(hidden_file)){

				foreach(string line in file_read(hidden_file).split("\n")){

					if (line.strip() == file_name){
						continue;
					}
					else{
						txt += (txt.length == 0) ? "" : "\n";
						txt += "%s".printf(line);
					}
				}
			}

			file_write(hidden_file, txt, null, null, true); // overwrite in-place
			parent.read_hidden_list();
			update_access_time();
			return true;
		}

		return false;
	}

	private void update_access_time(){
		// update access time (and changed time) - forces cached icon to expire
		touch(file_path, true, false, false, false, null); 
		query_file_info();
	}

	// set properties -------------------------
	
	private enum ModeMask{
		FILE_MODE_SUID       = 04000,
		FILE_MODE_SGID       = 02000,
		FILE_MODE_STICKY     = 01000,
		FILE_MODE_USR_ALL    = 00700,
		FILE_MODE_USR_READ   = 00400,
		FILE_MODE_USR_WRITE  = 00200,
		FILE_MODE_USR_EXEC   = 00100,
		FILE_MODE_GRP_ALL    = 00070,
		FILE_MODE_GRP_READ   = 00040,
		FILE_MODE_GRP_WRITE  = 00020,
		FILE_MODE_GRP_EXEC   = 00010,
		FILE_MODE_OTH_ALL    = 00007,
		FILE_MODE_OTH_READ   = 00004,
		FILE_MODE_OTH_WRITE  = 00002,
		FILE_MODE_OTH_EXEC   = 00001
	}

	private void parse_permissions(){

		perms = new string[10];
		perms[0] = "";
		perms[1] = ((this.unix_mode & ModeMask.FILE_MODE_USR_READ) != 0)  ? "r" : "-";
		perms[2] = ((this.unix_mode & ModeMask.FILE_MODE_USR_WRITE) != 0) ? "w" : "-";
		perms[3] = ((this.unix_mode & ModeMask.FILE_MODE_USR_EXEC) != 0)  ? "x" : "-";
		perms[4] = ((this.unix_mode & ModeMask.FILE_MODE_GRP_READ) != 0)  ? "r" : "-";
		perms[5] = ((this.unix_mode & ModeMask.FILE_MODE_GRP_WRITE) != 0) ? "w" : "-";
		perms[6] = ((this.unix_mode & ModeMask.FILE_MODE_GRP_EXEC) != 0)  ? "x" : "-";
		perms[7] = ((this.unix_mode & ModeMask.FILE_MODE_OTH_READ) != 0)  ? "r" : "-";
		perms[8] = ((this.unix_mode & ModeMask.FILE_MODE_OTH_WRITE) != 0) ? "w" : "-";
		perms[9] = ((this.unix_mode & ModeMask.FILE_MODE_OTH_EXEC) != 0)  ? "x" : "-";

		if ((this.unix_mode & ModeMask.FILE_MODE_SUID) != 0){
			perms[3] = "s";
		}

		if ((this.unix_mode & ModeMask.FILE_MODE_SGID) != 0){
			perms[6] = "s";
		}

		if ((this.unix_mode & ModeMask.FILE_MODE_STICKY) != 0){
			perms[9] = "t";
		}

		string txt = "";
		int index = 0;
		foreach(var ch in perms){
			index++;
			txt += ch;
			if (((index - 1) % 3) == 0){
				txt += " ";
			}
		}
		this.permissions = txt.strip();
	}
	
	public void set_content_type_from_extension(){
		
		if (content_type.length > 0){ return; }
		
		if (file_type == FileType.DIRECTORY){
			content_type = "inode/directory";
		}
		else{
			bool result_uncertain = false;
			content_type = GLib.ContentType.guess(file_name, null, out result_uncertain);
			if (result_uncertain){
				content_type = "";
				return;
			}
		}

		set_content_type_desc();
		
		set_content_type_icon();
	}
	
	public void set_content_type_desc(){
		if ((content_type.length > 0) && MimeType.mimetypes.has_key(this.content_type)){
			this.content_type_desc = MimeType.mimetypes[this.content_type].comment;
		}
	}
	
	public void set_content_type_icon(){
		if ((icon == null) && (content_type.length > 0)){
			icon = GLib.ContentType.get_icon(content_type);
		}
	}

	public void generate_checksum(ChecksumType checksum_type){

		var hash = file_checksum(file_path, checksum_type);

		switch(checksum_type){
		case ChecksumType.MD5:
			checksum_md5 = hash;
			break;
		case ChecksumType.SHA1:
			checksum_sha1 = hash;
			break;
		case ChecksumType.SHA256:
			checksum_sha256= hash;
			break;
		case ChecksumType.SHA512:
			checksum_sha512 = hash;
			break;
		}
	}
	
	// monitor

	public FileMonitor? monitor_for_changes(out Cancellable monitor_cancellable){

		if (!is_directory){
			return null;
		}

		FileMonitor file_monitor = null;

		var file = File.parse_name(file_path);

		try{
			monitor_cancellable = new Cancellable();
			var monitor_flags = FileMonitorFlags.WATCH_MOUNTS | FileMonitorFlags.WATCH_MOVES;
			file_monitor = file.monitor_directory(monitor_flags, monitor_cancellable);
		}
		catch (Error e){
			log_error(e.message);
			return null;
		}

		return file_monitor;
	}

	// compare

	public void compare_directory(FileItem dir2, uint64 size_limit = 2000000){

		if (dir2 == null){
			return;
		}

		foreach(var item in this.children.values){
			if (!item.content_type.has_prefix("text") || (item.file_size > size_limit)) { continue; }
			item.checksum_md5 = file_checksum(item.file_path);
		}

		foreach(var item in dir2.children.values){
			if (!item.content_type.has_prefix("text") || (item.file_size > size_limit)) { continue; }
			item.checksum_md5 = file_checksum(item.file_path);
		}

		compare_files_with_set(this, dir2, size_limit);
		compare_files_with_set(dir2, this, size_limit);
	}

	private void compare_files_with_set(FileItem dir1, FileItem dir2, uint64 size_limit){

		foreach(var file1 in dir1.children.values){

			if (!file1.content_type.has_prefix("text") || (file1.file_size > size_limit)){
				file1.compared_status = "skipped";
			}
			else if (dir2.children.has_key(file1.file_name)){

				var file2 = dir2.children[file1.file_name];

				file1.compared_file_path = file2.file_path;

				if (file1.checksum_md5 != file2.checksum_md5){
					file1.compared_status = "mismatch";
				}
				else{
					file1.compared_status = "match";
				}
			}
			else{
				file1.compared_status = "new";
			}
		}
	}

	// archives

	/*public void add_items_to_archive(Gee.ArrayList<FileItem> item_list){
		
		if (item_list.size > 0){
			foreach(var item in item_list){
				var child = add_child_from_disk(item.file_path);
				child.archive_base_item = this.archive_base_item;
			}
		}
	}*/

/*
	public ArchiveTask extract_archive_to_same_location(){

		var task = new ArchiveTask();
		task.compress(file_path);
		return task;
		
		this.extraction_path = current_item.file_path;

		// select a subfolder in source path for extraction
			archiver.extraction_path = "%s/%s".printf(
				file_parent(archive.file_path),
				file_title(archive.file_path));

			// since user has not specified the directory we need to
			// make sure that files are not overwritten accidentally
			// in existing directories
			 
			// create a unique extraction directory
			int count = 0;
			string outpath = archiver.extraction_path;
			while (dir_exists(outpath)||file_exists(outpath)){
				log_debug("dir_exists: %s".printf(outpath));
				outpath = "%s (%d)".printf(archiver.extraction_path, ++count);
			}
			log_debug("create_dir: %s".printf(outpath));
			archiver.extraction_path = outpath;
	}
	
	public ArchiveTask extract_archive(){
		var task = new ArchiveTask();
		task.compress(this);
		return task;
	}
	*/
}

public class FileItemMonitor : GLib.Object {
	public FileItem file_item;
	public FileMonitor monitor;
	public Cancellable? cancellable;
}

public enum ChecksumCompareResult {
	OK,
	CHANGED,
	MISSING,
	SYMLINK,
	ERROR,
	UNKNOWN
}
