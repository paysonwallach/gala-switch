/*
 * switch
 *
 * Copyright (c) 2014 Tom Beckmann
 * Copyright (c) 2021 Payson Wallach
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

namespace Switch {
    private class Settings : Granite.Services.Settings {
        protected string window_switcher_indicator_background_color { get; set; }

        public bool all_workspaces { get; set; }
        public bool animate { get; set; }
        public bool always_on_primary_monitor { get; set; }
        public int icon_size { get; set; }
        public Clutter.Color window_switcher_indicator_background_color_rgba {
            get {
                var rgba = Gdk.RGBA ();

                rgba.parse (window_switcher_indicator_background_color);

                return {
                           (uint8) (rgba.red * 255),
                           (uint8) (rgba.green * 255),
                           (uint8) (rgba.blue * 255),
                           (uint8) (rgba.alpha * 255)
                };
            }
        }

        private static Settings? instance = null;

        private Settings () {
            base ("org.pantheon.desktop.gala.plugins.switch");
        }

        public static Settings get_default () {
            if (instance == null)
                instance = new Settings ();

            return instance;
        }

    }

    private class RoundedActor : Clutter.Actor {
        private int? corner_radius = null;
        private double? corner_radius_ratio = null;
        private Clutter.Canvas canvas = new Clutter.Canvas ();

        public Clutter.Color color;

        public RoundedActor.with_fixed_radius (Clutter.Color color, int radius) {
            this.color = color;
            this.corner_radius = radius;
        }

        public RoundedActor.with_variable_radius (Clutter.Color color, double ratio = 0.175) {
            this.color = color;
            this.corner_radius_ratio = ratio;
        }

        construct {
            bind_property ("width", canvas, "width", BindingFlags.DEFAULT);
            bind_property ("height", canvas, "height", BindingFlags.DEFAULT);
            canvas.draw.connect (on_draw);
            set_content (canvas);
        }

        private bool on_draw (Cairo.Context cr, int surface_width, int surface_height) {
            const double degrees = Math.PI / 180.0;

            var x = 1.0;
            var y = 1.0;
            var width = surface_width - 2.0;
            var height = surface_height - 2.0;
            var radius = corner_radius_ratio == null
                ? corner_radius * Gala.Utils.get_ui_scaling_factor ()
                : height * corner_radius_ratio;

            cr.save ();
            cr.set_operator (Cairo.Operator.CLEAR);
            cr.paint ();
            cr.restore ();

            cr.new_sub_path ();
            cr.arc (x + width - radius, y + radius, radius, -90 * degrees, 0 * degrees);
            cr.arc (x + width - radius, y + height - radius, radius, 0 * degrees, 90 * degrees);
            cr.arc (x + radius, y + height - radius, radius, 90 * degrees, 180 * degrees);
            cr.arc (x + radius, y + radius, radius, 180 * degrees, 270 * degrees);
            cr.close_path ();

            cr.set_source_rgba (
                color.red / 255.0,
                color.green / 255.0,
                color.blue / 255.0,
                color.alpha / 255.0);
            cr.fill ();

            return true;
        }

    }

    private abstract class Switcher : Object {
        protected const int EASING_DURATION = 75;
        protected const int SPACING = 12;
        protected const int PADDING = 24;
        protected const int MIN_OFFSET = 64;
        protected const double ANIMATE_SCALE = 0.8;
        protected const Clutter.Color WRAPPER_BACKGROUND_COLOR = { 26, 26, 26, 150 };
        protected const Clutter.Color INDICATOR_BACKGROUND_COLOR = { 250, 250, 250, 150 };

        protected abstract Settings settings { get; protected set; }
        protected abstract Gala.WindowManager? wm { get; protected set; }
        protected abstract Gala.ModalProxy modal_proxy { get; protected set; }
        protected abstract Gee.HashMap<string, Gee.LinkedList<uint64?>> last_focused_window { get; protected set; }

        protected abstract Clutter.Actor container { get; protected set; }
        protected abstract Clutter.Actor wrapper { get; protected set; }
        protected abstract Clutter.Actor indicator { get; protected set; }
        protected abstract float indicator_padding { get; protected set; }

        protected abstract Clutter.Actor? current { get; protected set; default = null; }

        private delegate void ObjectCallback (Object object);

        private uint modifier_mask = 0U;
        private bool opened = false;

#if HAS_MUTTER330
        public abstract void on_open (Meta.Display display, Meta.Workspace workspace);

#else
        public abstract void on_open (Meta.Display display, Meta.Screen screen, Meta.Workspace workspace);

#endif

        public abstract Meta.Window? on_close ();

#if HAS_MUTTER330
        public void handle_switch (Meta.Display display, Meta.Window? window,
                                   Clutter.KeyEvent? event, Meta.KeyBinding binding) {
            var workspace = settings.all_workspaces ? null :
                            display.get_workspace_manager ().get_active_workspace ();
#else
        public void handle_switch (Meta.Display display, Meta.Screen screen, Meta.Window? window,
                                   X.Event event, Meta.KeyBinding binding) {
            var workspace = settings.all_workspaces ? null : screen.get_active_workspace ();
#endif

            // copied from gnome-shell, finds the primary modifier in the mask
            var mask = binding.get_mask ();
            if (mask == 0)
                modifier_mask = 0;
            else {
                modifier_mask = 1;
                while (mask > 1) {
                    mask >>= 1;
                    modifier_mask <<= 1;
                }
            }

            if (!opened)
                on_open (display, workspace);

            var binding_name = binding.get_name ();
            var backward = binding_name.has_suffix ("-backward");

            // FIXME: for unknown reasons, switch-applications-backward won't
            //        be emitted, so we test manually if shift is held down
            if (binding_name == "switch-applications")
                backward = ((get_current_modifiers () & Clutter.ModifierType.SHIFT_MASK) != 0);

            next_window (backward);
        }

        public void open_switcher () {
            if (container.get_n_children () == 0)
                return;

            if (opened)
                return;

#if HAS_MUTTER330
            var display = wm.get_display ();
#else
            var screen = wm.get_screen ();
#endif

            indicator.visible = false;

            if (settings.animate) {
                wrapper.opacity = 0;
                wrapper.set_scale (ANIMATE_SCALE, ANIMATE_SCALE);
            }

#if HAS_MUTTER330
            var monitor = settings.always_on_primary_monitor ?
                          display.get_primary_monitor () :
                          display.get_current_monitor ();
            var geom = display.get_monitor_geometry (monitor);
#else
            var monitor = settings.always_on_primary_monitor ?
                          screen.get_primary_monitor () :
                          screen.get_current_monitor ();
            var geom = screen.get_monitor_geometry (monitor);
#endif

            float container_width;
            container.get_preferred_width (
                settings.icon_size + PADDING * 2, null, out container_width);

            if (container_width + MIN_OFFSET * 2 > geom.width)
                container.width = geom.width - MIN_OFFSET * 2;

            float nat_width, nat_height;
            container.get_preferred_size (
                null, null, out nat_width, out nat_height);

            wrapper.set_size (nat_width, nat_height);
            wrapper.set_position (geom.x + (geom.width - wrapper.width) / 2,
                                  geom.y + (geom.height - wrapper.height) / 2);

            wm.ui_group.insert_child_above (wrapper, null);

            wrapper.save_easing_state ();
            wrapper.set_easing_duration (100);
            wrapper.set_scale (1, 1);
            wrapper.opacity = 255;
            wrapper.scroll_event.connect ((event) => {
                switch (event.direction) {
                case Clutter.ScrollDirection.UP:
                case Clutter.ScrollDirection.LEFT:
                    next_window ();
                    return true;
                case Clutter.ScrollDirection.DOWN:
                case Clutter.ScrollDirection.RIGHT:
                    next_window (true);
                    return true;
                default:
                    return false;
                }
            });
            wrapper.restore_easing_state ();

            modal_proxy = wm.push_modal ();
            modal_proxy.keybinding_filter = keybinding_filter;
            opened = true;

            wrapper.grab_key_focus ();

            // if we did not have the grab before the key was released,
            // close immediately
            if ((get_current_modifiers () & modifier_mask) == 0)
#if HAS_MUTTER330
                close_switcher (display.get_current_time ());
#else
                close_switcher (screen.get_display ().get_current_time ());
#endif
        }

        public void close_switcher (uint32 time, bool escape = false) {
            if (!opened)
                return;

            wm.pop_modal (modal_proxy);
            opened = false;

            ObjectCallback remove_actor = () => {
                wm.ui_group.remove_child (wrapper);
            };

            if (settings.animate) {
                wrapper.save_easing_state ();
                wrapper.set_easing_duration (100);
                wrapper.set_scale (ANIMATE_SCALE, ANIMATE_SCALE);
                wrapper.opacity = 0;

                var transition = wrapper.get_transition ("opacity");
                if (transition != null)
                    transition.completed.connect (() => remove_actor (this));
                else
                    remove_actor (this);

                wrapper.restore_easing_state ();
            } else
                remove_actor (this);

            if (escape)
                return;

            var window = on_close ();
            if (window == null)
                return;

            var workspace = window.get_workspace ();
#if HAS_MUTTER330
            if (workspace != wm.get_display ()
                 .get_workspace_manager ().get_active_workspace ())
#else
            if (workspace != wm.get_screen ().get_active_workspace ())
#endif
                workspace.activate_with_focus (window, time);
            else
                window.activate (time);
        }

        void next_window (bool backward = false) {
            Clutter.Actor actor;
            if (!backward) {
                actor = current.get_next_sibling ();
                if (actor == null)
                    actor = container.get_child_at_index (0);
            } else {
                actor = current.get_previous_sibling ();
                if (actor == null)
                    actor = container.get_child_at_index (container.get_n_children () - 1);
            }

            current = actor;

            update_indicator_position ();
        }

        public void update_indicator_position (bool initial = false) {
            // FIXME: there are some troubles with layouting, in some cases we
            //        are here too early, in which case all the children are at
            //        (0|0), so we can easily check for that and come back later
            if (container.get_n_children () > 1
                && container.get_child_at_index (1).allocation.x1 < 1) {

                Idle.add (() => {
                    update_indicator_position (initial);
                    return Source.REMOVE;
                });

                return;
            }

            float x, y;
            current.allocation.get_origin (out x, out y);

            if (!x.is_finite () || !y.is_finite ()) {
                Idle.add (() => {
                    update_indicator_position (initial);
                    return Source.REMOVE;
                });

                return;
            }

            if (initial) {
                indicator.save_easing_state ();
                indicator.set_easing_duration (0);
                indicator.visible = true;
            }

            var child = current.get_first_child ();

            float width, height;
            child.allocation.get_size (out width, out height);

            indicator.x = container.margin_left + x + child.x - indicator_padding;
            indicator.y = container.margin_top + y + child.y - indicator_padding;
            indicator.width = width + indicator_padding * 2;
            indicator.height = height + indicator_padding * 2;

            if (initial)
                indicator.restore_easing_state ();
        }

        public bool key_relase_event (Clutter.KeyEvent event) {
            if ((get_current_modifiers () & modifier_mask) == 0) {
                close_switcher (event.time);
                return true;
            }

            switch (event.keyval) {
            case Clutter.Key.Escape:
                close_switcher (event.time, true);
                return true;
            case Clutter.Key.Left:
                next_window (true);
                return true;
            case Clutter.Key.Right:
                next_window ();
                return true;
            default:
                return false;
            }
        }

        Gdk.ModifierType get_current_modifiers () {
            Gdk.ModifierType modifiers;
            double[] axes = {};
            Gdk.Display.get_default ().get_default_seat ().get_pointer ()
             .get_state (Gdk.get_default_root_window (), axes, out modifiers);

            return modifiers;
        }

        bool keybinding_filter (Meta.KeyBinding binding) {
            // don't block any keybinding for the time being
            // return true for any keybinding that should be handled here.
            return false;
        }

    }

    class ApplicationSwitcher : Switcher {
        override Settings settings { get; protected set; }
        override Gala.WindowManager? wm { get; protected set; }
        override Gala.ModalProxy modal_proxy { get; protected set; }
        override Gee.HashMap<string, Gee.LinkedList<uint64?>> last_focused_window { get; protected set; }

        override Clutter.Actor container { get; protected set; }
        override Clutter.Actor wrapper { get; protected set; }
        override Clutter.Actor indicator { get; protected set; }
        override float indicator_padding { get; protected set; default = 6; }

        override Clutter.Actor? current { get; protected set; default = null; }

        public ApplicationSwitcher (Gala.WindowManager wm, Settings settings, Gee.HashMap<string, Gee.LinkedList<uint64?>> last_focused_window) {
            this.wm = wm;
            this.settings = settings;
            this.last_focused_window = last_focused_window;

            var layout = new Clutter.FlowLayout (Clutter.FlowOrientation.HORIZONTAL);
            layout.column_spacing = layout.row_spacing = SPACING;

            wrapper = new RoundedActor.with_variable_radius (WRAPPER_BACKGROUND_COLOR);
            wrapper.reactive = true;
            wrapper.set_pivot_point (0.5f, 0.5f);
            wrapper.key_release_event.connect (key_relase_event);

            container = new Clutter.Actor ();
            container.layout_manager = layout;
            container.margin_left = container.margin_top =
                container.margin_right = container.margin_bottom = PADDING;

            indicator = new RoundedActor.with_variable_radius (INDICATOR_BACKGROUND_COLOR);
            indicator.set_easing_duration (EASING_DURATION);

            wrapper.add_child (indicator);
            wrapper.add_child (container);
        }

#if HAS_MUTTER330
        public override void on_open (Meta.Display display, Meta.Workspace workspace) {
            var windows = display.get_tab_list (Meta.TabList.NORMAL, workspace);
            var current_window = display.get_tab_current (Meta.TabList.NORMAL, workspace);
#else
        public override void on_open (Meta.Display display, Meta.Screen screen, Meta.Workspace workspace) {
            var windows = display.get_tab_list (Meta.TabList.NORMAL, screen, workspace);
            var current_window = display.get_tab_current (Meta.TabList.NORMAL, screen, workspace);
#endif

            container.width = -1;
            container.destroy_all_children ();

            var icons_added = new Gee.HashSet<string> ();
            foreach (var window in windows) {
                var window_class = window.get_wm_class ();
                if (icons_added.contains (window_class))
                    continue;

                var wrapper = new Clutter.Actor ();
                var icon = new Gala.WindowIcon (window, settings.icon_size);

                wrapper.reactive = true;
                wrapper.button_release_event.connect ((event) => {
                    current = wrapper;

                    close_switcher (event.time);

                    return true;
                });

                if (window == current_window)
                    current = wrapper;

                wrapper.add_child (icon);
                container.add_child (wrapper);

                icons_added.add (window_class);
            }

            open_switcher ();
            update_indicator_position (true);
        }

        public override Meta.Window? on_close () {
            var window_icon = current.get_first_child () as Gala.WindowIcon;
            if (window_icon == null)
                return null;

            var window = window_icon.window;
            var window_class = window.get_wm_class ();
#if HAS_MUTTER330
            var display = wm.get_display ();
            var workspace = settings.all_workspaces ? null :
                            display.get_workspace_manager ().get_active_workspace ();
            var windows = display.get_tab_list (Meta.TabList.NORMAL, workspace);
#else
            var screen = wm.get_screen ();
            var workspace = settings.all_workspaces ? null : wm.get_screen ().get_active_workspace ();
            var windows = wm.get_display ().get_tab_list (Meta.TabList.NORMAL, screen, workspace);
#endif
            foreach (var focused_window in last_focused_window.@get (window_class)) {
                foreach (var meta_window in windows) {
                    if (meta_window.get_id () == focused_window) {
                        window = meta_window;
                        break;
                    }
                }
                break;
            }

            return window;
        }

    }

    class WindowSwitcher : Switcher {
        const int APPLICATION_SWITCHER_CORNER_RADIUS = 6;
        const Clutter.Color APPLICATION_SWITCHER_INDICATOR_BACKGROUND_COLOR = { 249, 196, 64, 150 };

        override Settings settings { get; protected set; }
        override Gala.WindowManager? wm { get; protected set; }
        override Gala.ModalProxy modal_proxy { get; protected set; }
        override Gee.HashMap<string, Gee.LinkedList<uint64?>> last_focused_window { get; protected set; }

        override Clutter.Actor container { get; protected set; }
        override Clutter.Actor wrapper { get; protected set; }
        override Clutter.Actor indicator { get; protected set; }
        override float indicator_padding { get; protected set; default = 6; }

        override Clutter.Actor? current { get; protected set; default = null; }

        public WindowSwitcher (Gala.WindowManager wm, Settings settings, Gee.HashMap<string, Gee.LinkedList<uint64?>> last_focused_window) {
            this.wm = wm;
            this.settings = settings;
            this.last_focused_window = last_focused_window;

            var layout = new Clutter.FlowLayout (Clutter.FlowOrientation.HORIZONTAL);
            layout.column_spacing = layout.row_spacing = SPACING;

            wrapper = new RoundedActor.with_fixed_radius (
                WRAPPER_BACKGROUND_COLOR, APPLICATION_SWITCHER_CORNER_RADIUS);
            wrapper.reactive = true;
            wrapper.set_pivot_point (0.5f, 0.5f);
            wrapper.key_release_event.connect (key_relase_event);

            container = new Clutter.Actor ();
            container.layout_manager = layout;
            container.margin_left = container.margin_top =
                container.margin_right = container.margin_bottom = PADDING;

            indicator = new RoundedActor.with_fixed_radius (
                settings.window_switcher_indicator_background_color_rgba, APPLICATION_SWITCHER_CORNER_RADIUS);
            indicator.set_easing_duration (EASING_DURATION);

            settings.changed.connect (() => {
                var indicator = indicator as RoundedActor;
                if (indicator != null)
                    indicator.color = settings.window_switcher_indicator_background_color_rgba;
            });

            wrapper.add_child (indicator);
            wrapper.add_child (container);
        }

#if HAS_MUTTER330
        public override void on_open (Meta.Display display, Meta.Workspace workspace) {
            var windows = display.get_tab_list (Meta.TabList.NORMAL, workspace);
            var current_window = display.get_tab_current (Meta.TabList.NORMAL, workspace);
#else
        public override void on_open (Meta.Display display, Meta.Screen screen, Meta.Workspace workspace) {
            var windows = display.get_tab_list (TabList.NORMAL, screen, workspace);
            var current_window = display.get_tab_current (TabList.NORMAL, screen, workspace);
#endif
            var current_window_wm_class = current_window.get_wm_class ();
            var focus_order = last_focused_window.@get (current_window_wm_class);
            unowned List<Meta.WindowActor> window_actors = display.get_window_actors ();

            container.width = -1;
            container.destroy_all_children ();
            foreach (var id in focus_order) {
                unowned List<weak Meta.Window>? results = windows.search<uint64?>(id, (a, b) => {
                    return a.get_id () == b ? 0 : 1;
                });

                Meta.Window window;
                if (results.length () > 0)
                    window = results.data;
                else
                    continue;

                foreach (var window_actor in window_actors) {
                    var meta_window = window_actor.get_meta_window ();
                    if (meta_window == window) {
                        var wrapper = new Clutter.Actor ();
                        var clone = new Clutter.Clone (window_actor);

                        wrapper.reactive = true;
                        wrapper.x_expand = wrapper.y_expand = true;
                        wrapper.button_release_event.connect ((event) => {
                            current = wrapper;

                            close_switcher (event.time);

                            return true;
                        });

                        float width, height;
                        clone.get_preferred_size (null, null, out width, out height);
                        clone.set_size (width * 0.3f, height * 0.3f);

                        if (meta_window == current_window)
                            current = wrapper;

                        wrapper.add_child (clone);
                        container.add_child (wrapper);
                        break;
                    }
                }
            }

            open_switcher ();
            update_children_position ();
        }

        public override Meta.Window? on_close () {
            var clone = current.get_first_child () as Clutter.Clone;
            if (clone == null)
                return null;

            var window_actor = clone.get_source () as Meta.WindowActor;
            if (window_actor == null)
                return null;

            return window_actor.get_meta_window ();
        }

        private void update_children_position () {
            // FIXME: there are some troubles with layouting, in some cases we
            //        are here too early, in which case all the children are at
            //        (0|0), so we can easily check for that and come back later
            if (container.get_n_children () > 1
                && container.get_child_at_index (1).allocation.x1 < 1) {

                Idle.add (() => {
                    update_children_position ();

                    return Source.REMOVE;
                });

                return;
            }

            foreach (var child in container.get_children ()) {
                var window = child.get_first_child ();

                float child_width, child_height;
                child.allocation.get_size (out child_width, out child_height);

                float window_height, window_width;
                window.allocation.get_size (out window_width, out window_height);

                if (!child_width.is_finite () || !child_height.is_finite () || !window_width.is_finite () || !window_height.is_finite ()) {
                    Idle.add (() => {
                        update_children_position ();

                        return Source.REMOVE;
                    });

                    return;
                }

                window.set_position (
                    (child_width - window_width) / 2,
                    (child_height - window_height) / 2);
            }

            update_indicator_position (true);
        }

    }

    public class Main : Gala.Plugin {
        private Gala.WindowManager? wm = null;
        private Gee.HashMap<string, Gee.LinkedList<uint64?>> last_focused_window = new Gee.HashMap<string, Gee.LinkedList<uint64?>> ();

        public override void initialize (Gala.WindowManager wm) {
            this.wm = wm;
            var settings = Settings.get_default ();
            var application_switcher = new ApplicationSwitcher (wm, settings, last_focused_window);
            var window_switcher = new WindowSwitcher (wm, settings, last_focused_window);

            Meta.KeyBinding.set_custom_handler ("switch-applications", application_switcher.handle_switch);
            Meta.KeyBinding.set_custom_handler ("switch-applications-backward", application_switcher.handle_switch);
            Meta.KeyBinding.set_custom_handler ("switch-windows", window_switcher.handle_switch);
            Meta.KeyBinding.set_custom_handler ("switch-windows-backward", window_switcher.handle_switch);

#if HAS_MUTTER330
            var display = wm.get_display ();
            foreach (unowned Meta.WindowActor actor in display.get_window_actors ()) {
                if (actor.is_destroyed ())
                    continue;

                unowned Meta.Window window = actor.get_meta_window ();
                if (window.window_type == Meta.WindowType.NORMAL)
                    monitor_window (window);
            }

            display.window_created.connect (on_window_created);
#else
            var screen = wm.get_screen ();
            foreach (unowned Meta.WindowActor actor in screen.get_window_actors ()) {
                if (actor.is_destroyed ())
                    continue;

                unowned Meta.Window window = actor.get_meta_window ();
                if (window.window_type == Meta.WindowType.NORMAL)
                    monitor_window (window);
            }

            screen.get_display ().window_created.connect (on_window_created);
#endif
        }

        public override void destroy () {
#if HAS_MUTTER330
            var display = wm.get_display ();
            foreach (unowned Meta.WindowActor actor in display.get_window_actors ()) {
                if (actor.is_destroyed ())
                    continue;

                unowned Meta.Window window = actor.get_meta_window ();
                if (window.window_type == Meta.WindowType.NORMAL)
                    monitor_window (window);
            }

            display.window_created.disconnect (on_window_created);
#else
            var screen = wm.get_screen ();
            foreach (unowned Meta.WindowActor actor in screen.get_window_actors ()) {
                if (actor.is_destroyed ())
                    continue;

                unowned Meta.Window window = actor.get_meta_window ();
                if (window.window_type == Meta.WindowType.NORMAL)
                    unmonitor_window (window);
            }

            screen.get_display ().window_created.disconnect (on_window_created);
#endif
            if (wm == null)
                return;
        }

        private void on_window_created (Meta.Window window) {
            if (window.window_type == Meta.WindowType.NORMAL)
                monitor_window (window);
        }

        private void monitor_window (Meta.Window window) {
            var focused_window_id = window.get_id ();
            var focused_window_wm_class = window.get_wm_class ();
            var last_focused_windows = last_focused_window.@get (focused_window_wm_class);

            if (last_focused_windows == null)
                last_focused_windows = new Gee.LinkedList<uint64?>();

            last_focused_windows.insert (0, focused_window_id);
            last_focused_window.@set (focused_window_wm_class, last_focused_windows);

            window.focused.connect (window_focused);
            window.unmanaged.connect (unmonitor_window);
        }

        private void unmonitor_window (Meta.Window window) {
            var focused_window_id = window.get_id ();
            var focused_window_wm_class = window.get_wm_class ();
            var last_focused_windows = last_focused_window.@get (focused_window_wm_class);

            last_focused_windows.remove (focused_window_id);
            last_focused_window.@set (focused_window_wm_class, last_focused_windows);

            window.focused.disconnect (window_focused);
            window.unmanaged.disconnect (unmonitor_window);
        }

        private void window_focused (Meta.Window window) {
            var focused_window_id = window.get_id ();
            var focused_window_wm_class = window.get_wm_class ();
            var last_focused_windows = last_focused_window.@get (focused_window_wm_class);

            last_focused_windows.sort ((a, b) => {
                return a == focused_window_id ? -1 : b == focused_window_id ? 1 : 0;
            });
            last_focused_window.@set (focused_window_wm_class, last_focused_windows);
        }

    }
}

public Gala.PluginInfo register_plugin () {
    return Gala.PluginInfo () {
               name = "Switch",
               author = "Payson Wallach <payson@paysonwallach.com>",
               plugin_type = typeof (Switch.Main),
               provides = Gala.PluginFunction.WINDOW_SWITCHER,
               load_priority = Gala.LoadPriority.IMMEDIATE
    };
}
