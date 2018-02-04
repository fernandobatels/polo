/*
 * MessageBar.vala
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


using Gtk;
using Gee;

using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.JsonHelper;
using TeeJee.ProcessHelper;
using TeeJee.GtkHelper;
using TeeJee.System;
using TeeJee.Misc;

public class MessageBar : Gtk.Box {

	// reference properties ----------

	protected MainWindow window {
		get { return App.main_window; }
	}
	
	protected FileViewPane pane;

	protected FileViewList view {
		get{ return pane.view; }
	}

	protected LayoutPanel panel {
		get { return pane.panel; }
	}
	
	private string message_text = "";
	private Gtk.MessageType type = Gtk.MessageType.INFO; // INFO, ERROR, WARNING, QUESTION, OTHER
	private Gtk.ScrolledWindow scrolled;
	
	// -------------------------------

	public MessageBar(FileViewPane parent_pane, string msg, Gtk.MessageType _type){
		//base(Gtk.Orientation.VERTICAL, 6); // issue with vala
		Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 6); // work-around
		margin = 0;

		log_debug("MessageBar()");

		message_text = msg;
		type = _type;
		
		pane = parent_pane;

		init_ui();

		show_all();

		//gtk_hide(this);
	}

	private void init_ui(){

		scrolled = new Gtk.ScrolledWindow(null, null);
		//scrolled.set_shadow_type (ShadowType.ETCHED_IN);
		scrolled.hscrollbar_policy = PolicyType.AUTOMATIC;
		scrolled.vscrollbar_policy = PolicyType.AUTOMATIC;
		scrolled.margin = 6;
		add(scrolled);

		if (message_text.strip().split("\n").length > 5){
			scrolled.set_size_request(-1, 100);
		}
		else if (message_text.strip().split("\n").length > 1){
			scrolled.set_size_request(-1, 50);
		}

		var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
		scrolled.add(box);
		
		var label = new Gtk.Label(message_text);
		label.xalign = 0.0f;
		label.hexpand = true;
		label.margin = 0;
		box.add(label);

		string css = "";

		switch (type){
		case Gtk.MessageType.INFO:
			css = " background-color: #81C784; "; // green-black
			break;
		case Gtk.MessageType.ERROR:
			css = " background-color: #E57373; "; // red-black
			break;
		case Gtk.MessageType.WARNING:
			css = " background-color: #FFEB3B; "; // yellow-black
			break;
		case Gtk.MessageType.QUESTION:
			css = " background-color: #03A9F4; "; // blue-black
			break;
		case Gtk.MessageType.OTHER:
			css = " background-color: #9E9E9E; "; // grey-black
			break;
		}
		
		gtk_apply_css(new Gtk.Widget[] { this }, css);

		css = " color: #000000; ";
		gtk_apply_css(new Gtk.Widget[] { label }, css);

		add_close_button(box);
	}

	private void add_close_button(Gtk.Box box){

		//var img = new Gtk.Image.from_pixbuf(IconManager.lookup("window-close", 16, true));

		var ebox = new Gtk.EventBox();
		//ebox.add(img);
		//this.add(ebox);

		var label = new Gtk.Label("<span weight=\"bold\">%s</span>".printf("X"));
		label.set_use_markup(true);
		label.margin = 6;
		ebox.add(label);
		add(ebox);
		
		var css = " color: #000000; ";
		gtk_apply_css(new Gtk.Widget[] { label }, css);

		ebox.set_tooltip_text(_("Close"));

		set_pointer_cursor_for_eventbox(ebox);

		ebox.button_press_event.connect((event)=>{
			this.hide();
			pane.messages.remove(this);
			pane.message_box.remove(this);
			return true;
		});
	}
}

