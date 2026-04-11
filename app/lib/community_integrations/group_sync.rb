# frozen_string_literal: true

module CommunityIntegrations
  # Shared helper for adding / removing a user from a Discourse group.
  # Centralises the membership check so no checker module duplicates the logic.
  module GroupSync
    # Adds or removes +user+ from the group identified by +group_name+.
    #
    # @param user       [User]    the Discourse user to sync
    # @param group_name [String]  the Discourse group name from site settings
    # @param is_member  [Boolean, nil]
    #   true  → ensure the user IS in the group
    #   false → ensure the user is NOT in the group
    #   nil   → API error; take no action (avoid incorrectly removing members)
    def self.sync(user, group_name, is_member)
      return if is_member.nil?
      return if group_name.blank?

      group = Group.find_by(name: group_name)
      unless group
        Rails.logger.warn(
          "CommunityIntegrations::GroupSync: group '#{group_name}' not found — " \
            "create it in Admin → Groups.",
        )
        return
      end

      if is_member
        group.add(user) unless group.users.include?(user)
      else
        group.remove(user) if group.users.include?(user)
      end
    rescue => e
      Rails.logger.error(
        "CommunityIntegrations::GroupSync: error syncing user #{user.id} " \
          "to group '#{group_name}': #{e.message}",
      )
    end
  end
end
