#!/usr/bin/env bash
# Builds a wineserver that keeps each process's memory views in a tree, for
# Wine 11.22 (the version this patch is ported to). VIctory maps the title's
# memory as tens of thousands of views, and Wine's server walked all of them
# on every map and unmap. With this one the server went from about 56 % of
# a core to 3 %, and the opening cutscene's frames from 1.9 s to 0.85 s
# (one A/B, see LINUX.md "Speed").
#
# The change is ajsem's "server: Keep memory views in a tree by base address"
# (CachyOS/wine-cachyos fd66dbc, based on a version by neonb; Wine bug 60868),
# ported to Wine 11.22. Wine is LGPL-2.1-or-later.
#
# Only wineserver is built, and nothing is installed: linux/run.sh starts it
# for the prefix when VICTORY_WINESERVER points at it.
# Usage: linux/build-wineserver.sh [output dir]  (default ~/.local/share/victory/wineserver)
set -euo pipefail
ver=11.22
have=$(wine --version 2>/dev/null || true)
[ "$have" = "wine-$ver" ] || { echo "this patch is for Wine $ver; you have ${have:-no wine}" >&2; exit 1; }
out=${1:-$HOME/.local/share/victory/wineserver}
src=$(mktemp -d)
trap 'rm -rf "$src"' EXIT
git clone -q --depth 1 --branch "wine-$ver" https://gitlab.winehq.org/wine/wine.git "$src/wine"
cd "$src/wine"
git apply <<'PATCH'
diff --git a/server/file.h b/server/file.h
index 99215b8..32fd977 100644
--- a/server/file.h
+++ b/server/file.h
@@ -179,6 +179,7 @@ extern struct memory_view *get_exe_view( struct process *process );
 extern struct file *get_view_file( const struct memory_view *view, unsigned int access, unsigned int sharing );
 extern const struct pe_image_info *get_view_image_info( const struct memory_view *view, client_ptr_t *base );
 extern int get_view_nt_name( const struct memory_view *view, struct unicode_str *name );
+extern void init_process_views( struct process *process );
 extern void free_mapped_views( struct process *process );
 extern size_t get_page_size(void);
 extern struct mapping *create_fd_mapping( struct object *root, struct unicode_str name, struct fd *fd,
diff --git a/server/mapping.c b/server/mapping.c
index d1b0fc3..9bc2fbf 100644
--- a/server/mapping.c
+++ b/server/mapping.c
@@ -98,6 +98,7 @@ static struct list shared_map_list = LIST_INIT( shared_map_list );
 struct memory_view
 {
     struct list     entry;           /* entry in per-process view list */
+    struct rb_entry tree_entry;      /* entry in per-process view tree, by base */
     struct fd      *fd;              /* fd for mapped file */
     struct ranges  *committed;       /* list of committed ranges in this mapping */
     struct shared_map *shared;       /* temp file for shared PE mapping */
@@ -384,14 +385,48 @@ static int create_temp_file( file_pos_t size )
     return fd;
 }
 
+static int compare_view_base( const void *key, const struct rb_entry *entry )
+{
+    client_ptr_t base = *(const client_ptr_t *)key;
+    const struct memory_view *view = RB_ENTRY_VALUE( entry, const struct memory_view, tree_entry );
+
+    if (base < view->base) return -1;
+    if (base > view->base) return 1;
+    return 0;
+}
+
+/* initialize the view list and tree of a new process */
+void init_process_views( struct process *process )
+{
+    list_init( &process->views );
+    rb_init( &process->view_tree, compare_view_base );
+}
+
+/* find the view with the highest base address not above addr */
+static struct memory_view *find_view_below( struct process *process, client_ptr_t addr )
+{
+    struct rb_entry *entry = process->view_tree.root;
+    struct memory_view *view, *found = NULL;
+
+    while (entry)
+    {
+        view = RB_ENTRY_VALUE( entry, struct memory_view, tree_entry );
+        if (view->base <= addr)
+        {
+            found = view;
+            entry = entry->right;
+        }
+        else entry = entry->left;
+    }
+    return found;
+}
+
 /* find a memory view from its base address */
 struct memory_view *find_mapped_view( struct process *process, client_ptr_t base )
 {
-    struct memory_view *view;
-
-    LIST_FOR_EACH_ENTRY( view, &process->views, struct memory_view, entry )
-        if (view->base == base) return view;
+    struct rb_entry *entry = rb_get( &process->view_tree, &base );
 
+    if (entry) return RB_ENTRY_VALUE( entry, struct memory_view, tree_entry );
     set_error( STATUS_NOT_MAPPED_VIEW );
     return NULL;
 }
@@ -399,11 +434,9 @@ struct memory_view *find_mapped_view( struct process *process, client_ptr_t base
 /* find a memory view from any address inside it */
 static struct memory_view *find_mapped_addr( struct process *process, client_ptr_t addr )
 {
-    struct memory_view *view;
-
-    LIST_FOR_EACH_ENTRY( view, &process->views, struct memory_view, entry )
-        if (addr >= view->base && addr < view->base + view->size) return view;
+    struct memory_view *view = find_view_below( process, addr );
 
+    if (view && addr < view->base + view->size) return view;
     set_error( STATUS_NOT_MAPPED_VIEW );
     return NULL;
 }
@@ -417,14 +450,10 @@ static int is_valid_view_addr( struct process *process, client_ptr_t addr, mem_s
     if (addr & (process->page_size - 1)) return 0;
     if (addr + size < addr) return 0;  /* overflow */
 
-    /* check for overlapping view */
-    LIST_FOR_EACH_ENTRY( view, &process->views, struct memory_view, entry )
-    {
-        if (view->base + view->size <= addr) continue;
-        if (view->base >= addr + size) continue;
-        return 0;
-    }
-    return 1;
+    /* views don't overlap, so only the last one starting inside the range
+     * or before it can overlap it */
+    view = find_view_below( process, addr + size - 1 );
+    return !view || view->base + view->size <= addr;
 }
 
 /* get the main exe memory view */
@@ -462,19 +491,22 @@ static int add_process_view( struct thread *thread, struct memory_view *view )
                 process->imagelen = name.len;
             process->image_info = view->image;
             list_add_head( &process->views, &view->entry );
+            rb_put( &process->view_tree, &view->base, &view->tree_entry );
             return 1;
         }
     }
     list_add_tail( &process->views, &view->entry );
+    rb_put( &process->view_tree, &view->base, &view->tree_entry );
     return 0;
 }
 
-static void free_memory_view( struct memory_view *view )
+static void free_memory_view( struct process *process, struct memory_view *view )
 {
     if (view->fd) release_object( view->fd );
     if (view->committed) release_object( view->committed );
     if (view->shared) release_object( view->shared );
     list_remove( &view->entry );
+    rb_remove( &process->view_tree, &view->tree_entry );
     free( view );
 }
 
@@ -484,7 +516,7 @@ void free_mapped_views( struct process *process )
     struct list *ptr;
 
     while ((ptr = list_head( &process->views )))
-        free_memory_view( LIST_ENTRY( ptr, struct memory_view, entry ));
+        free_memory_view( process, LIST_ENTRY( ptr, struct memory_view, entry ));
 }
 
 /* find the shared PE mapping for a given mapping */
@@ -1797,7 +1829,7 @@ DECL_HANDLER(unmap_view)
 
     if (!view) return;
     generate_dll_event( current, DbgUnloadDllStateChange, view );
-    free_memory_view( view );
+    free_memory_view( current->process, view );
 }
 
 /* get information about a mapped image view */
diff --git a/server/process.c b/server/process.c
index 510faf1..7fb1e4e 100644
--- a/server/process.c
+++ b/server/process.c
@@ -647,7 +647,7 @@ struct process *create_process( int fd, struct process *parent, unsigned int fla
     list_init( &process->locks );
     list_init( &process->asyncs );
     list_init( &process->classes );
-    list_init( &process->views );
+    init_process_views( process );
 
     process->end_time = 0;
 
diff --git a/server/process.h b/server/process.h
index dff766d..9e40fe4 100644
--- a/server/process.h
+++ b/server/process.h
@@ -22,6 +22,7 @@
 #define __WINE_SERVER_PROCESS_H
 
 #include "object.h"
+#include "wine/rbtree.h"
 
 struct atom_table;
 struct handle_table;
@@ -79,7 +80,8 @@ struct process
     obj_handle_t         winstation;      /* main handle to process window station */
     obj_handle_t         desktop;         /* handle to desktop to use for new threads */
     struct token        *token;           /* security token associated with this process */
-    struct list          views;           /* list of memory views */
+    struct list          views;           /* list of memory views, main exe first */
+    struct rb_tree       view_tree;       /* memory views by base address */
     client_ptr_t         peb;             /* PEB address in client address space */
     struct dir_cache    *dir_cache;       /* map of client-side directory cache */
     unsigned int         trace_data;      /* opaque data used by the process tracing mechanism */
PATCH
./configure -q --enable-win64 --without-mingw --disable-tests --without-x --without-freetype \
    --without-wayland --without-vulkan --without-gstreamer >/dev/null
make -j"$(nproc)" server/wineserver >/dev/null
mkdir -p "$out"
cp server/wineserver "$out/wineserver"
echo "built: $out/wineserver (set VICTORY_WINESERVER=$out/wineserver in linux/env.sh)"
