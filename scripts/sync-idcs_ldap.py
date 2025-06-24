#!/usr/bin/env python3
"""
IDCS ↔ LDAP Synchronization Script
OCI IDCS SSO Platform

This script synchronizes users and groups between OCI IDCS and OpenLDAP.
"""

import os
import sys
import json
import logging
import asyncio
import argparse
from datetime import datetime, timezone
from typing import List, Dict, Any, Optional, Tuple
from dataclasses import dataclass

import asyncpg
import aiohttp
import ldap3
from ldap3 import Server, Connection, ALL, MODIFY_REPLACE, MODIFY_ADD, MODIFY_DELETE

# Add the backend directory to the Python path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'backend'))

try:
    from app.core.config import settings
    from app.services.auth.idcs_service import IDCSService
    from app.services.auth.ldap_service import LDAPService
except ImportError as e:
    print(f"Error importing backend modules: {e}")
    print("Make sure you're running this script from the project root directory")
    sys.exit(1)


@dataclass
class SyncUser:
    """User data structure for synchronization"""
    user_id: str
    username: str
    email: str
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    display_name: Optional[str] = None
    groups: List[str] = None
    source: str = 'unknown'
    attributes: Dict[str, Any] = None
    
    def __post_init__(self):
        if self.groups is None:
            self.groups = []
        if self.attributes is None:
            self.attributes = {}


@dataclass
class SyncGroup:
    """Group data structure for synchronization"""
    group_id: str
    group_name: str
    display_name: Optional[str] = None
    description: Optional[str] = None
    members: List[str] = None
    source: str = 'unknown'
    attributes: Dict[str, Any] = None
    
    def __post_init__(self):
        if self.members is None:
            self.members = []
        if self.attributes is None:
            self.attributes = {}


@dataclass
class SyncStats:
    """Synchronization statistics"""
    users_processed: int = 0
    users_created: int = 0
    users_updated: int = 0
    users_deleted: int = 0
    groups_processed: int = 0
    groups_created: int = 0
    groups_updated: int = 0
    groups_deleted: int = 0
    errors: List[str] = None
    
    def __post_init__(self):
        if self.errors is None:
            self.errors = []


class IDCSLDAPSynchronizer:
    """
    Main synchronization class for IDCS ↔ LDAP sync
    """
    
    def __init__(self, dry_run: bool = False):
        self.dry_run = dry_run
        self.logger = self._setup_logging()
        self.stats = SyncStats()
        
        # Services
        self.idcs_service = None
        self.ldap_service = None
        self.db_connection = None
        
        # Configuration
        self.user_mapping = settings.sync_user_mapping_dict
        self.group_mapping = settings.sync_group_mapping_dict
        
    def _setup_logging(self) -> logging.Logger:
        """Setup logging configuration"""
        logger = logging.getLogger('idcs_ldap_sync')
        logger.setLevel(getattr(logging, settings.SYNC_LOG_LEVEL))
        
        # Create formatter
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        
        # Console handler
        console_handler = logging.StreamHandler()
        console_handler.setFormatter(formatter)
        logger.addHandler(console_handler)
        
        # File handler
        log_file = os.path.join(
            os.path.dirname(__file__), '..', 'logs', 'ldap-sync.log'
        )
        os.makedirs(os.path.dirname(log_file), exist_ok=True)
        file_handler = logging.FileHandler(log_file)
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)
        
        return logger
    
    async def initialize(self):
        """Initialize services and connections"""
        self.logger.info("Initializing synchronization services...")
        
        try:
            # Initialize IDCS service
            if settings.FEATURE_OAUTH_LOGIN or settings.FEATURE_SAML_LOGIN:
                self.idcs_service = IDCSService()
                await self.idcs_service.initialize()
                self.logger.info("IDCS service initialized")
            
            # Initialize LDAP service
            if settings.FEATURE_DIRECT_LDAP_LOGIN or settings.FEATURE_LDAP_SYNC:
                self.ldap_service = LDAPService()
                await self.ldap_service.initialize()
                self.logger.info("LDAP service initialized")
            
            # Initialize database connection
            self.db_connection = await asyncpg.connect(settings.DATABASE_URL)
            self.logger.info("Database connection established")
            
        except Exception as e:
            self.logger.error(f"Failed to initialize services: {e}")
            raise
    
    async def cleanup(self):
        """Cleanup resources"""
        if self.db_connection:
            await self.db_connection.close()
        self.logger.info("Cleanup completed")
    
    async def sync_users_idcs_to_ldap(self) -> bool:
        """Synchronize users from IDCS to LDAP"""
        if not self.idcs_service or not self.ldap_service:
            self.logger.warning("IDCS or LDAP service not available for user sync")
            return False
        
        self.logger.info("Starting IDCS → LDAP user synchronization...")
        
        try:
            # Get users from IDCS
            idcs_users = await self._get_idcs_users()
            self.logger.info(f"Retrieved {len(idcs_users)} users from IDCS")
            
            # Get existing users from LDAP
            ldap_users = await self._get_ldap_users()
            ldap_user_map = {user.username: user for user in ldap_users}
            
            # Process each IDCS user
            for idcs_user in idcs_users:
                self.stats.users_processed += 1
                
                try:
                    if idcs_user.username in ldap_user_map:
                        # Update existing user
                        await self._update_ldap_user(idcs_user, ldap_user_map[idcs_user.username])
                        self.stats.users_updated += 1
                    else:
                        # Create new user
                        await self._create_ldap_user(idcs_user)
                        self.stats.users_created += 1
                        
                except Exception as e:
                    error_msg = f"Failed to sync user {idcs_user.username}: {e}"
                    self.logger.error(error_msg)
                    self.stats.errors.append(error_msg)
            
            # Handle deletions if enabled
            if settings.SYNC_DELETE_MISSING_USERS:
                await self._delete_missing_ldap_users(idcs_users, ldap_users)
            
            self.logger.info("IDCS → LDAP user synchronization completed")
            return True
            
        except Exception as e:
            self.logger.error(f"User synchronization failed: {e}")
            return False
    
    async def sync_groups_idcs_to_ldap(self) -> bool:
        """Synchronize groups from IDCS to LDAP"""
        if not self.idcs_service or not self.ldap_service:
            self.logger.warning("IDCS or LDAP service not available for group sync")
            return False
        
        self.logger.info("Starting IDCS → LDAP group synchronization...")
        
        try:
            # Get groups from IDCS
            idcs_groups = await self._get_idcs_groups()
            self.logger.info(f"Retrieved {len(idcs_groups)} groups from IDCS")
            
            # Get existing groups from LDAP
            ldap_groups = await self._get_ldap_groups()
            ldap_group_map = {group.group_name: group for group in ldap_groups}
            
            # Process each IDCS group
            for idcs_group in idcs_groups:
                self.stats.groups_processed += 1
                
                try:
                    if idcs_group.group_name in ldap_group_map:
                        # Update existing group
                        await self._update_ldap_group(idcs_group, ldap_group_map[idcs_group.group_name])
                        self.stats.groups_updated += 1
                    else:
                        # Create new group
                        await self._create_ldap_group(idcs_group)
                        self.stats.groups_created += 1
                        
                except Exception as e:
                    error_msg = f"Failed to sync group {idcs_group.group_name}: {e}"
                    self.logger.error(error_msg)
                    self.stats.errors.append(error_msg)
            
            # Handle deletions if enabled
            if settings.SYNC_DELETE_MISSING_GROUPS:
                await self._delete_missing_ldap_groups(idcs_groups, ldap_groups)
            
            self.logger.info("IDCS → LDAP group synchronization completed")
            return True
            
        except Exception as e:
            self.logger.error(f"Group synchronization failed: {e}")
            return False
    
    async def sync_users_ldap_to_idcs(self) -> bool:
        """Synchronize users from LDAP to IDCS"""
        # Note: This is typically read-only from LDAP to IDCS
        # Implementation depends on IDCS API capabilities
        self.logger.info("LDAP → IDCS user sync not implemented (typically read-only)")
        return True
    
    async def sync_groups_ldap_to_idcs(self) -> bool:
        """Synchronize groups from LDAP to IDCS"""
        # Note: This is typically read-only from LDAP to IDCS
        # Implementation depends on IDCS API capabilities
        self.logger.info("LDAP → IDCS group sync not implemented (typically read-only)")
        return True
    
    async def _get_idcs_users(self) -> List[SyncUser]:
        """Get users from IDCS"""
        users = []
        try:
            # Use IDCS service to get users
            idcs_users_data = await self.idcs_service.list_users()
            
            for user_data in idcs_users_data.get('Resources', []):
                user = SyncUser(
                    user_id=user_data.get('id'),
                    username=user_data.get('userName'),
                    email=user_data.get('emails', [{}])[0].get('value'),
                    first_name=user_data.get('name', {}).get('givenName'),
                    last_name=user_data.get('name', {}).get('familyName'),
                    display_name=user_data.get('displayName'),
                    groups=[group.get('display') for group in user_data.get('groups', [])],
                    source='idcs',
                    attributes=user_data
                )
                users.append(user)
                
        except Exception as e:
            self.logger.error(f"Failed to get IDCS users: {e}")
            raise
        
        return users
    
    async def _get_idcs_groups(self) -> List[SyncGroup]:
        """Get groups from IDCS"""
        groups = []
        try:
            # Use IDCS service to get groups
            idcs_groups_data = await self.idcs_service.list_groups()
            
            for group_data in idcs_groups_data.get('Resources', []):
                group = SyncGroup(
                    group_id=group_data.get('id'),
                    group_name=group_data.get('displayName'),
                    display_name=group_data.get('displayName'),
                    description=group_data.get('description'),
                    members=[member.get('value') for member in group_data.get('members', [])],
                    source='idcs',
                    attributes=group_data
                )
                groups.append(group)
                
        except Exception as e:
            self.logger.error(f"Failed to get IDCS groups: {e}")
            raise
        
        return groups
    
    async def _get_ldap_users(self) -> List[SyncUser]:
        """Get users from LDAP"""
        users = []
        try:
            # Use LDAP service to get users
            ldap_users_data = await self.ldap_service.search_users()
            
            for user_data in ldap_users_data:
                user = SyncUser(
                    user_id=user_data.get('uid'),
                    username=user_data.get('uid'),
                    email=user_data.get('mail'),
                    first_name=user_data.get('givenName'),
                    last_name=user_data.get('sn'),
                    display_name=user_data.get('displayName'),
                    groups=user_data.get('groups', []),
                    source='ldap',
                    attributes=user_data
                )
                users.append(user)
                
        except Exception as e:
            self.logger.error(f"Failed to get LDAP users: {e}")
            raise
        
        return users
    
    async def _get_ldap_groups(self) -> List[SyncGroup]:
        """Get groups from LDAP"""
        groups = []
        try:
            # Use LDAP service to get groups
            ldap_groups_data = await self.ldap_service.search_groups()
            
            for group_data in ldap_groups_data:
                group = SyncGroup(
                    group_id=group_data.get('cn'),
                    group_name=group_data.get('cn'),
                    display_name=group_data.get('cn'),
                    description=group_data.get('description'),
                    members=group_data.get('members', []),
                    source='ldap',
                    attributes=group_data
                )
                groups.append(group)
                
        except Exception as e:
            self.logger.error(f"Failed to get LDAP groups: {e}")
            raise
        
        return groups
    
    async def _create_ldap_user(self, user: SyncUser):
        """Create a new user in LDAP"""
        if self.dry_run:
            self.logger.info(f"[DRY RUN] Would create LDAP user: {user.username}")
            return
        
        try:
            # Map IDCS attributes to LDAP attributes
            ldap_attributes = self._map_user_attributes_idcs_to_ldap(user)
            
            # Create user in LDAP
            await self.ldap_service.create_user(user.username, ldap_attributes)
            self.logger.info(f"Created LDAP user: {user.username}")
            
            # Update database
            await self._update_user_in_database(user)
            
        except Exception as e:
            self.logger.error(f"Failed to create LDAP user {user.username}: {e}")
            raise
    
    async def _update_ldap_user(self, idcs_user: SyncUser, ldap_user: SyncUser):
        """Update an existing user in LDAP"""
        if self.dry_run:
            self.logger.info(f"[DRY RUN] Would update LDAP user: {idcs_user.username}")
            return
        
        try:
            # Compare attributes and build modification list
            modifications = self._build_user_modifications(idcs_user, ldap_user)
            
            if modifications:
                # Update user in LDAP
                await self.ldap_service.modify_user(idcs_user.username, modifications)
                self.logger.info(f"Updated LDAP user: {idcs_user.username}")
                
                # Update database
                await self._update_user_in_database(idcs_user)
            else:
                self.logger.debug(f"No changes needed for user: {idcs_user.username}")
                
        except Exception as e:
            self.logger.error(f"Failed to update LDAP user {idcs_user.username}: {e}")
            raise
    
    async def _create_ldap_group(self, group: SyncGroup):
        """Create a new group in LDAP"""
        if self.dry_run:
            self.logger.info(f"[DRY RUN] Would create LDAP group: {group.group_name}")
            return
        
        try:
            # Map IDCS attributes to LDAP attributes
            ldap_attributes = self._map_group_attributes_idcs_to_ldap(group)
            
            # Create group in LDAP
            await self.ldap_service.create_group(group.group_name, ldap_attributes)
            self.logger.info(f"Created LDAP group: {group.group_name}")
            
            # Update database
            await self._update_group_in_database(group)
            
        except Exception as e:
            self.logger.error(f"Failed to create LDAP group {group.group_name}: {e}")
            raise
    
    async def _update_ldap_group(self, idcs_group: SyncGroup, ldap_group: SyncGroup):
        """Update an existing group in LDAP"""
        if self.dry_run:
            self.logger.info(f"[DRY RUN] Would update LDAP group: {idcs_group.group_name}")
            return
        
        try:
            # Compare attributes and build modification list
            modifications = self._build_group_modifications(idcs_group, ldap_group)
            
            if modifications:
                # Update group in LDAP
                await self.ldap_service.modify_group(idcs_group.group_name, modifications)
                self.logger.info(f"Updated LDAP group: {idcs_group.group_name}")
                
                # Update database
                await self._update_group_in_database(idcs_group)
            else:
                self.logger.debug(f"No changes needed for group: {idcs_group.group_name}")
                
        except Exception as e:
            self.logger.error(f"Failed to update LDAP group {idcs_group.group_name}: {e}")
            raise
    
    async def _delete_missing_ldap_users(self, idcs_users: List[SyncUser], ldap_users: List[SyncUser]):
        """Delete users from LDAP that don't exist in IDCS"""
        idcs_usernames = {user.username for user in idcs_users}
        
        for ldap_user in ldap_users:
            if ldap_user.username not in idcs_usernames:
                if self.dry_run:
                    self.logger.info(f"[DRY RUN] Would delete LDAP user: {ldap_user.username}")
                else:
                    try:
                        await self.ldap_service.delete_user(ldap_user.username)
                        self.logger.info(f"Deleted LDAP user: {ldap_user.username}")
                        self.stats.users_deleted += 1
                    except Exception as e:
                        error_msg = f"Failed to delete LDAP user {ldap_user.username}: {e}"
                        self.logger.error(error_msg)
                        self.stats.errors.append(error_msg)
    
    async def _delete_missing_ldap_groups(self, idcs_groups: List[SyncGroup], ldap_groups: List[SyncGroup]):
        """Delete groups from LDAP that don't exist in IDCS"""
        idcs_group_names = {group.group_name for group in idcs_groups}
        
        for ldap_group in ldap_groups:
            if ldap_group.group_name not in idcs_group_names:
                if self.dry_run:
                    self.logger.info(f"[DRY RUN] Would delete LDAP group: {ldap_group.group_name}")
                else:
                    try:
                        await self.ldap_service.delete_group(ldap_group.group_name)
                        self.logger.info(f"Deleted LDAP group: {ldap_group.group_name}")
                        self.stats.groups_deleted += 1
                    except Exception as e:
                        error_msg = f"Failed to delete LDAP group {ldap_group.group_name}: {e}"
                        self.logger.error(error_msg)
                        self.stats.errors.append(error_msg)
    
    def _map_user_attributes_idcs_to_ldap(self, user: SyncUser) -> Dict[str, Any]:
        """Map IDCS user attributes to LDAP format"""
        ldap_attrs = {}
        
        # Basic mappings
        if user.email:
            ldap_attrs['mail'] = user.email
        if user.first_name:
            ldap_attrs['givenName'] = user.first_name
        if user.last_name:
            ldap_attrs['sn'] = user.last_name
        if user.display_name:
            ldap_attrs['displayName'] = user.display_name
        
        # Apply custom mappings from configuration
        for ldap_attr, idcs_path in self.user_mapping.items():
            try:
                value = self._get_nested_value(user.attributes, idcs_path)
                if value:
                    ldap_attrs[ldap_attr] = value
            except Exception as e:
                self.logger.debug(f"Failed to map attribute {ldap_attr}: {e}")
        
        return ldap_attrs
    
    def _map_group_attributes_idcs_to_ldap(self, group: SyncGroup) -> Dict[str, Any]:
        """Map IDCS group attributes to LDAP format"""
        ldap_attrs = {}
        
        # Basic mappings
        if group.display_name:
            ldap_attrs['cn'] = group.display_name
        if group.description:
            ldap_attrs['description'] = group.description
        
        # Apply custom mappings from configuration
        for ldap_attr, idcs_path in self.group_mapping.items():
            try:
                value = self._get_nested_value(group.attributes, idcs_path)
                if value:
                    ldap_attrs[ldap_attr] = value
            except Exception as e:
                self.logger.debug(f"Failed to map group attribute {ldap_attr}: {e}")
        
        return ldap_attrs
    
    def _get_nested_value(self, data: Dict[str, Any], path: str) -> Any:
        """Get nested value from dictionary using dot notation"""
        keys = path.split('.')
        value = data
        
        for key in keys:
            if '[' in key and ']' in key:
                # Handle array notation like emails[0].value
                array_key, index_part = key.split('[')
                index = int(index_part.split(']')[0])
                value = value.get(array_key, [])[index]
            else:
                value = value.get(key)
                
            if value is None:
                break
        
        return value
    
    def _build_user_modifications(self, idcs_user: SyncUser, ldap_user: SyncUser) -> List[Tuple[str, str, Any]]:
        """Build LDAP modification list for user updates"""
        modifications = []
        
        # Compare email
        if idcs_user.email != ldap_user.email:
            modifications.append((MODIFY_REPLACE, 'mail', [idcs_user.email]))
        
        # Compare first name
        if idcs_user.first_name != ldap_user.first_name:
            modifications.append((MODIFY_REPLACE, 'givenName', [idcs_user.first_name]))
        
        # Compare last name
        if idcs_user.last_name != ldap_user.last_name:
            modifications.append((MODIFY_REPLACE, 'sn', [idcs_user.last_name]))
        
        # Compare display name
        if idcs_user.display_name != ldap_user.display_name:
            modifications.append((MODIFY_REPLACE, 'displayName', [idcs_user.display_name]))
        
        return modifications
    
    def _build_group_modifications(self, idcs_group: SyncGroup, ldap_group: SyncGroup) -> List[Tuple[str, str, Any]]:
        """Build LDAP modification list for group updates"""
        modifications = []
        
        # Compare display name
        if idcs_group.display_name != ldap_group.display_name:
            modifications.append((MODIFY_REPLACE, 'cn', [idcs_group.display_name]))
        
        # Compare description
        if idcs_group.description != ldap_group.description:
            modifications.append((MODIFY_REPLACE, 'description', [idcs_group.description]))
        
        # Compare members
        idcs_members = set(idcs_group.members)
        ldap_members = set(ldap_group.members)
        
        if idcs_members != ldap_members:
            # Calculate member differences
            members_to_add = idcs_members - ldap_members
            members_to_remove = ldap_members - idcs_members
            
            if members_to_add:
                modifications.append((MODIFY_ADD, 'member', list(members_to_add)))
            if members_to_remove:
                modifications.append((MODIFY_DELETE, 'member', list(members_to_remove)))
        
        return modifications
    
    async def _update_user_in_database(self, user: SyncUser):
        """Update user information in database"""
        try:
            query = """
            INSERT INTO sso_platform.users (user_id, email, first_name, last_name, display_name, source, updated_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            ON CONFLICT (user_id) DO UPDATE SET
                email = EXCLUDED.email,
                first_name = EXCLUDED.first_name,
                last_name = EXCLUDED.last_name,
                display_name = EXCLUDED.display_name,
                updated_at = EXCLUDED.updated_at
            """
            
            await self.db_connection.execute(
                query,
                user.user_id,
                user.email,
                user.first_name,
                user.last_name,
                user.display_name,
                user.source,
                datetime.now(timezone.utc)
            )
            
        except Exception as e:
            self.logger.error(f"Failed to update user in database: {e}")
    
    async def _update_group_in_database(self, group: SyncGroup):
        """Update group information in database"""
        try:
            query = """
            INSERT INTO sso_platform.groups (group_name, display_name, description, source, updated_at)
            VALUES ($1, $2, $3, $4, $5)
            ON CONFLICT (group_name) DO UPDATE SET
                display_name = EXCLUDED.display_name,
                description = EXCLUDED.description,
                updated_at = EXCLUDED.updated_at
            """
            
            await self.db_connection.execute(
                query,
                group.group_name,
                group.display_name,
                group.description,
                group.source,
                datetime.now(timezone.utc)
            )
            
        except Exception as e:
            self.logger.error(f"Failed to update group in database: {e}")
    
    async def _update_sync_status(self, sync_type: str, status: str, details: Dict[str, Any]):
        """Update synchronization status in database"""
        try:
            query = """
            UPDATE sso_platform.sync_status 
            SET last_sync = $1, status = $2, details = $3, updated_at = $4
            WHERE sync_type = $5
            """
            
            await self.db_connection.execute(
                query,
                datetime.now(timezone.utc),
                status,
                json.dumps(details),
                datetime.now(timezone.utc),
                sync_type
            )
            
        except Exception as e:
            self.logger.error(f"Failed to update sync status: {e}")
    
    def print_stats(self):
        """Print synchronization statistics"""
        print("\n" + "="*50)
        print("           SYNCHRONIZATION REPORT")
        print("="*50)
        print(f"Timestamp: {datetime.now().isoformat()}")
        print(f"Mode: {'DRY RUN' if self.dry_run else 'LIVE'}")
        print()
        print("USERS:")
        print(f"  Processed: {self.stats.users_processed}")
        print(f"  Created:   {self.stats.users_created}")
        print(f"  Updated:   {self.stats.users_updated}")
        print(f"  Deleted:   {self.stats.users_deleted}")
        print()
        print("GROUPS:")
        print(f"  Processed: {self.stats.groups_processed}")
        print(f"  Created:   {self.stats.groups_created}")
        print(f"  Updated:   {self.stats.groups_updated}")
        print(f"  Deleted:   {self.stats.groups_deleted}")
        print()
        print(f"ERRORS: {len(self.stats.errors)}")
        if self.stats.errors:
            for error in self.stats.errors:
                print(f"  - {error}")
        print("="*50)
    
    async def run_full_sync(self):
        """Run complete synchronization"""
        self.logger.info("Starting full synchronization...")
        
        try:
            await self.initialize()
            
            # Sync users IDCS → LDAP
            user_sync_success = await self.sync_users_idcs_to_ldap()
            
            # Sync groups IDCS → LDAP
            group_sync_success = await self.sync_groups_idcs_to_ldap()
            
            # Update sync status
            status = "success" if (user_sync_success and group_sync_success) else "partial_failure"
            details = {
                "stats": {
                    "users": {
                        "processed": self.stats.users_processed,
                        "created": self.stats.users_created,
                        "updated": self.stats.users_updated,
                        "deleted": self.stats.users_deleted
                    },
                    "groups": {
                        "processed": self.stats.groups_processed,
                        "created": self.stats.groups_created,
                        "updated": self.stats.groups_updated,
                        "deleted": self.stats.groups_deleted
                    }
                },
                "errors": self.stats.errors
            }
            
            await self._update_sync_status("full_sync", status, details)
            
            self.print_stats()
            self.logger.info("Full synchronization completed")
            
            return len(self.stats.errors) == 0
            
        except Exception as e:
            self.logger.error(f"Full synchronization failed: {e}")
            await self._update_sync_status("full_sync", "error", {"error": str(e)})
            return False
            
        finally:
            await self.cleanup()


async def main():
    """Main function"""
    parser = argparse.ArgumentParser(description="IDCS ↔ LDAP Synchronization Script")
    parser.add_argument("--dry-run", action="store_true", help="Run in dry-run mode (no changes)")
    parser.add_argument("--users-only", action="store_true", help="Sync users only")
    parser.add_argument("--groups-only", action="store_true", help="Sync groups only")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose logging")
    
    args = parser.parse_args()
    
    # Setup logging level
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    # Check if sync is enabled
    if not settings.SYNC_ENABLED:
        print("Synchronization is disabled in configuration")
        return 1
    
    synchronizer = IDCSLDAPSynchronizer(dry_run=args.dry_run)
    
    try:
        await synchronizer.initialize()
        
        success = True
        
        if args.users_only:
            success = await synchronizer.sync_users_idcs_to_ldap()
        elif args.groups_only:
            success = await synchronizer.sync_groups_idcs_to_ldap()
        else:
            success = await synchronizer.run_full_sync()
        
        return 0 if success else 1
        
    except Exception as e:
        print(f"Synchronization failed: {e}")
        return 1
    finally:
        await synchronizer.cleanup()


if __name__ == "__main__":
    import asyncio
    exit_code = asyncio.run(main())
    sys.exit(exit_code)