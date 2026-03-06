ARP_UserGuideText = [[
Welcome to the User Guide!

Table of Contents:

--------------------------
Section 1: Layout

  1.1 ARP Tracker Panel
    - Buttons
    - Primary List
    - Input Fields
    - Quantity Overrides

  1.2 Filter Panel
    - Buttons
    - Dropdown Lists

--------------------------
Section 2: Editing Lists

  - Adding Items to Lists
  - Deleting Items from Lists
  - Locking Active List
  - Per-Item, Per-List Quantity Overrides

--------------------------
Section 3: Exporting Data

  - Single Item
  - Filtered Lists
  - English Item Names
  - Delimiter Dropdown
  - Use English Number Format

-------------------------- 
Section 4: Important Notes: 

 - Automatic Price Clearing 
 - Minimap Button
 - Slash Commands

--------------------------
Section 1.1 ARP Tracker Panel

The main ARP Tracker Panel displays the addon version, two input fields, this user guide, and a scrollable item list. This section explains each part.

The Version Number updates with each AddOn release. It helps with error reporting and ensures you're using the latest version.

When you search the Auction House to build a Master or User List, new items are added to the scrollable section. Each item appears as a Parent Item with Child Items, each showing different information.

The Parent Item shows the item name without a rank. The edit box beside it displays the item name, all ranks, and the average prices of the Child Items. This is useful for exporting data to a spreadsheet for crafting cost calculations.

All ranks appear, even if not added to the list. If a rank is missing, its price will show as 0.00, ensuring every rank has a value when exporting.

The Child Items are nested under the Parent and can be expanded or collapsed. Each Child displays the Average Price, Minimum Price, and Maximum Price based on your Quantity and Trim settings. The X on the right side of a Child Item removes it from the list.

Quantity Override Dropdown:

Each item entry includes a Quantity Override dropdown that lets you customize the quantity used for that specific item’s price calculation. By default, all items use the global average quantity, but if you need finer control — for example, to reflect different crafting yields or vendor stack sizes — you can override it here.

    Default: Uses the shared quantity average across all items.

    Custom values: Select from preset quantities (e.g., 100, 250, 500, etc.) to override the default for this item only.

    Effect: The override updates the average price calculation and is reflected immediately in the summary and export.

**Per-Item, Per-List Quantity Overrides:**  

- Overrides are saved **per item, per list**. You can set different override quantities for the same item in different User Lists.  
- Switching lists does not affect overrides in other lists; each list keeps its own values.  
- The global Quantity input sets the default for new items, but existing overrides are preserved for each list individually.  

Example:  
- In the “Alchemy” User List, you set Charged Alloy to 500 units.  
- In “Blacksmithing,” the same item can use 1000 units.  
- Both values coexist independently for accurate calculations in each list.

The Input Fields are Quantity and Trim%:

Quantity determines how many items are used to calculate the average price (maximum 100,000).  
Example: Set 5,000 to calculate the average price of 5,000 Charged Alloy.

Trim% removes a percentage of high-end outliers, ensuring a more reliable average by filtering extreme prices.  

Example:  
If Charged Alloy (Rank 2) has 5,709 available and you set your Quantity to 6,000, all available prices are included.  
The lowest price is 90.99g, but a few are listed for 50,000g and one for 911,111g.  
Without a Trim, the average includes these extreme prices, producing a false average of 332.64g.  
Setting Trim% = 3 removes the top 3% of high-end prices, resulting in a much more accurate average of 110.98g.

Lock Active List:

A Lock Active List checkbox appears at the top of the panel.

Checked = New items cannot be added to the active list.

Unchecked = New items can be added.

This prevents accidental additions. When the panel is not visible the list is locked automatically to prevent background additions.


-- 1.2 Filter Panel --

The Filter Panel houses the rest of the addon's functions.

At the top is the Primary Filter, which controls which items from your Master List are visible:

All shows every item in the Master List, including all User List items.

User List shows only items from your active User List.

Below that are Trade Skill Filters, which organize items by Profession:

Herbs appear in Alchemy

Inks appear in Inscription

Cloth appears in Tailoring
…and so on.

Beneath the dropdowns are the Apply Filter and Clear Filter buttons:

After selecting a filter, click Apply Filter to activate it.

Click Clear Filter to return to the full Master List.

The Create List field lets you type the name of a new list.

Clicking Create List creates that list and makes it the active filter. New lists start empty.

Clicking Delete List removes the selected list from the User List dropdown. It does not need to be active to delete. Deleting a list only removes the list itself; items remain in the Master List.

Export All Button
Opens the Export All Data panel, which displays export strings used for spreadsheet creation. It compiles the information from all visible Parent Items in your active filter.

Update Prices Button
Refreshes the prices for all visible items in the active list. Whether Child Items are expanded or collapsed, they are included in the update.

External factors—such as other addons, packet loss, or latency—can cause updates to fail partially or completely. When this happens, a message appears in the chat frame. If some items fail to update, simply run the update again.


-- 2. Editing Lists --

Adding items works the same way for both Master and User Lists:

When in the Master (All) list, clicking an item in the Auction House adds it to the list.

Quantity and Trim% settings are automatically applied.

To add items to a User List:

Make the desired list active (new lists are active by default).

If needed, select the list from the dropdown and click Apply Filter.

Clicking an item in the AH while a User List is active adds it to both the User List and the Master List.

Deleting items works the same for both lists:

Click the X next to a Child Item's data box to remove it.

Removing an item from a User List does not affect the Master List.

Removing an item from the Master List removes it from all User Lists.

When the Lock Active List checkbox is enabled, no new items can be added to the active list, even if the panel is hidden.

Unlock to resume adding items.


-- 3. Exporting Data --

To export a single item, copy the export string from the Parent Item in your list. Paste it into a single row in your spreadsheet.

To export filtered items—such as Trade Skill filters or a User List—activate the filter by selecting it from the dropdown and pressing Apply Filter. Then click Export All to open the Export All Data panel.

This panel lists all visible Parent Item export strings, each on its own line, making it easy to import into your spreadsheet. Select all text, copy it, and paste it wherever needed.

Prices showing 0.00 represent items not added to your list or not fully updated. The export string ensures every rank includes a value, allowing your spreadsheet to populate rows completely without blank cells.
If a price seems missing, run the Update Prices function again.

Example:
Charged Alloy, Rank 1, 0.00, Rank 2, 109.31, Rank 3, 423.27
Dawnweave Bolt, Rank 1, 0.00, Rank 2, 0.00, Rank 3, 165.24
Gleaming Shard, Rank 1, 0.00, Rank 2, 20.31, Rank 3, 42.19


Export Panel Options:

Use English Names: Enable this checkbox to replace the localized item name with the official English item name associated with the itemID in the export string.

Example: On a German client, “Geladener Alloy” becomes “Charged Alloy” in the export.


Delimiter Dropdown Menu: You can set your desired Delimiter here to make the export string match your custom or prebuilt spreadsheets.


Use English Number Format: Enable this checkbox to swap from localized number formatting to English formatting if you are in a region that differs from the English Number Format.

Example: 10000,00 becomes 10000.00 when enabled.

These options ensure exported strings are consistent, readable, and fully compatible with spreadsheets.


-- 4. Important Notes: --

All pricing data is cleared each time you open the Auction House to ensure accuracy when updating prices.

A Minimap button was added to make showing or hiding the ARP Tracker Panel more user friendly than just the slash commands. You can Shift + Left Click to Drag it around the minimap. Left-click will Hide or Show the Panel while Right-click will open a dropdown giving you the option to Hide Minimap Button. You can restore the minimap button using the slash command.


Slash Commands:

/arp clear   - Wipes all ARP Tracker data, including items and user lists.

/arp show    - Shows the ARP Tracker panel if it is closed.

/arp hide    - Hides the ARP Tracker panel; also prevents adding items to lists in the background.

/arp minimap - Restores the Minimap button if you closed it.

/arp clean   - Performs a full cleanup of the item database:
               • Migrates legacy itemDB formats to the current structure.
               • Initializes missing quantityOverride fields.
               • Marks incomplete entries as cleared.
               • Removes malformed or empty item groups.
               • Updates the panel after cleanup.

/arp notice  - Shows the patch notice popup for the current version if available.

Thank you for using ARP Tracker!

If you have any questions, encounter a bug, or just want to share your feedback or appreciation, feel free to leave a comment on the addon page at CurseForge.

]]
