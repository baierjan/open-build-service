require 'rails_helper'

RSpec.describe NotificationService::Notifier do
  let(:user_bob) { create(:confirmed_user, login: 'bob') }
  let(:user_kim) { create(:confirmed_user, login: 'kim') }
  let(:commenter) { create(:confirmed_user, login: 'ann') }

  let(:create_bob_subscription) { create(:event_subscription_comment_for_project, receiver_role: 'maintainer', user: user_bob, channel: :rss) }
  let(:create_bob_web_subscription) { create(:event_subscription_comment_for_project, receiver_role: 'maintainer', user: user_bob, channel: :web) }
  let(:create_kim_subscription) { create(:event_subscription_comment_for_project, receiver_role: 'maintainer', user: user_kim, channel: :rss) }

  let(:project) { create(:project, name: 'bobkim_project') }
  let(:create_relationship_bob) { create(:relationship_project_user, user: user_bob, project: project) }
  let(:create_relationship_kim) { create(:relationship_project_user, user: user_kim, project: project) }

  let(:create_comment_for_project) { create(:comment_project, commentable: project, user: commenter, body: 'blah') }
  let(:event) { Event::Base.where(eventtype: 'Event::CommentForProject').last }

  describe '#call' do
    subject { NotificationService::Notifier.new(event).call }

    context 'when users has rss token' do
      before do
        create_bob_subscription
        create_bob_web_subscription
        create_kim_subscription
        create_relationship_bob
        create_relationship_kim
        create_comment_for_project

        user_bob.create_rss_token
        user_kim.create_rss_token

        subject
      end

      it 'creates only one CommentForProject notifications for subscriber' do
        expect(Notification.count).to eq(2)
      end

      it 'subscribes bob and kim to the rss notifications' do
        expect(Notification.where(event_type: 'Event::CommentForProject').pluck(:subscriber_id)).to match_array([user_bob.id, user_kim.id])
      end

      it 'creates one notification with rss checked for bob' do
        expect(Notification.find_by(subscriber: user_bob)).to be_rss
      end

      it 'creates one notification with web checked for bob' do
        expect(Notification.find_by(subscriber: user_bob)).to be_web
      end

      it 'creates one notification with rss checked for kim' do
        expect(Notification.find_by(subscriber: user_kim)).to be_rss
      end

      it 'does not create a notificaton with web checked for kim' do
        expect(Notification.find_by(subscriber: user_kim)).not_to be_web
      end

      it 'does not duplicate notifications' do
        expect { NotificationService::Notifier.new(event).call }.not_to change(Notification, :count)
      end
    end

    context "when users don't have rss token" do
      before do
        create_bob_web_subscription
        create_relationship_bob
        create_comment_for_project
        subject
      end

      it { expect(Notification.count).to eq(1) }
      it { expect(Notification.first).to be_web }
      it { expect(Notification.first).not_to be_rss }
    end

    context 'and I have an event for a relationship create' do
      let(:owner) { create(:confirmed_user) }

      context 'and I am dealing with projects' do
        let(:project) { create(:project_with_package) }

        context 'and the event triggers for a user' do
          let(:user) { create(:confirmed_user) }
          let(:event) { Event::RelationshipCreate.create!(who: owner, user: user.login, project: project.name, notifiable_id: project.id) }

          context 'and a user is subscribed to the event' do
            before do
              event_subscription = create(
                :event_subscription,
                eventtype: 'Event::RelationshipCreate',
                receiver_role: 'any_role',
                user: user,
                group: nil,
                channel: :web
              )
              event_subscription.payload = { project: project.name }
            end

            it 'creates a new notification for the target user' do
              expect { NotificationService::Notifier.new(event).call }.to change(Notification, :count).to(1)
            end
          end

          context 'and no user is subscribed to the event' do
            it 'does not create a new notification for the target user' do
              expect { NotificationService::Notifier.new(event).call }.not_to change(Notification, :count)
            end
          end
        end

        context 'and the event triggers for a group' do
          let(:group) { create(:group_with_user) }
          let(:user) { group.users.first }
          let(:event) { Event::RelationshipCreate.create!(who: owner, group: group.title, project: project.name, notifiable_id: project.id) }

          context 'and a group member is subscribed to the event' do
            before do
              event_subscription = create(
                :event_subscription,
                eventtype: 'Event::RelationshipCreate',
                receiver_role: 'any_role',
                user: user,
                group: nil,
                channel: :web
              )
              event_subscription.payload = { project: project.name }
              group.groups_users.first.update(email: false)
            end

            it 'creates a new notification for the subscribed group members' do
              expect { NotificationService::Notifier.new(event).call }.to change(Notification, :count).to(1)
            end
          end

          context 'and no group is subscribed to the event' do
            it 'does not create a new notification for the target user' do
              expect { NotificationService::Notifier.new(event).call }.not_to change(Notification, :count)
            end
          end
        end
      end

      context 'and I am dealing with packages' do
        let(:project) { create(:project_with_package) }
        let(:package) { project.packages.first }

        context 'and the event triggers for a user' do
          let(:user) { create(:confirmed_user) }
          let(:event) { Event::RelationshipCreate.create!(who: owner, user: user.login, package: package.name, project: project.name, notifiable_id: package.id) }

          context 'and a user is subscribed to the event' do
            before do
              event_subscription = create(
                :event_subscription,
                eventtype: 'Event::RelationshipCreate',
                receiver_role: 'any_role',
                user: user,
                group: nil,
                channel: :web
              )
              event_subscription.payload = { package: package.name }
            end

            it 'creates a new notification for the target user' do
              expect { NotificationService::Notifier.new(event).call }.to change(Notification, :count).to(1)
            end
          end

          context 'and no user is subscribed to the event' do
            it 'does not create a new notification for the target user' do
              expect { NotificationService::Notifier.new(event).call }.not_to change(Notification, :count)
            end
          end
        end

        context 'and the event triggers for a group' do
          let(:group) { create(:group_with_user) }
          let(:user) { group.users.first }
          let(:event) { Event::RelationshipCreate.create!(who: owner, group: group.title, package: package.name, project: project.name, notifiable_id: package.id) }

          context 'and a group is subscribed to the event' do
            before do
              event_subscription = create(
                :event_subscription,
                eventtype: 'Event::RelationshipCreate',
                receiver_role: 'any_role',
                user: user,
                group: nil,
                channel: :web
              )
              event_subscription.payload = { package: package.name }
            end

            it 'creates a new notification for the target user' do
              expect { NotificationService::Notifier.new(event).call }.to change(Notification, :count).to(1)
            end
          end

          context 'and no group is subscribed to the event' do
            it 'does not create a new notification for the target user' do
              expect { NotificationService::Notifier.new(event).call }.not_to change(Notification, :count)
            end
          end
        end
      end
    end

    context 'and I have an event for a relationship delete' do
      let(:owner) { create(:confirmed_user) }

      context 'and I am dealing with projects' do
        let(:project) { create(:project_with_package) }

        context 'and the event triggers for a user' do
          let(:user) { create(:confirmed_user) }
          let(:event) { Event::RelationshipDelete.create!(who: owner, user: user.login, project: project.name, notifiable_id: project.id) }

          context 'and a user is subscribed to the event' do
            before do
              event_subscription = create(
                :event_subscription,
                eventtype: 'Event::RelationshipDelete',
                receiver_role: 'any_role',
                user: user,
                group: nil,
                channel: :web
              )
              event_subscription.payload = { project: project.name }
            end

            it 'creates a new notification for the target user' do
              expect { NotificationService::Notifier.new(event).call }.to change(Notification, :count).to(1)
            end
          end

          context 'and no user is subscribed to the event' do
            it 'does not create a new notification for the target user' do
              expect { NotificationService::Notifier.new(event).call }.not_to change(Notification, :count)
            end
          end
        end

        context 'and the event triggers for a group' do
          let(:group) { create(:group_with_user) }
          let(:user) { group.users.first }
          let(:event) { Event::RelationshipDelete.create!(who: owner, group: group.title, project: project.name, notifiable_id: project.id) }

          context 'and a group member is subscribed to the event' do
            before do
              event_subscription = create(
                :event_subscription,
                eventtype: 'Event::RelationshipDelete',
                receiver_role: 'any_role',
                user: user,
                group: nil,
                channel: :web
              )
              event_subscription.payload = { project: project.name }
            end

            it 'creates a new notification for the subscribed group members' do
              expect { NotificationService::Notifier.new(event).call }.to change(Notification, :count).to(1)
            end
          end

          context 'and no group is subscribed to the event' do
            it 'does not create a new notification for the target user' do
              expect { NotificationService::Notifier.new(event).call }.not_to change(Notification, :count)
            end
          end
        end
      end

      context 'and I am dealing with packages' do
        let(:project) { create(:project_with_package) }
        let(:package) { project.packages.first }

        context 'and the event triggers for a user' do
          let(:user) { create(:confirmed_user) }
          let(:event) { Event::RelationshipDelete.create!(who: owner, user: user.login, package: package.name, project: project.name, notifiable_id: package.id) }

          context 'and a user is subscribed to the event' do
            before do
              event_subscription = create(
                :event_subscription,
                eventtype: 'Event::RelationshipDelete',
                receiver_role: 'any_role',
                user: user,
                group: nil,
                channel: :web
              )
              event_subscription.payload = { package: package.name }
            end

            it 'creates a new notification for the target user' do
              expect { NotificationService::Notifier.new(event).call }.to change(Notification, :count).to(1)
            end
          end

          context 'and no user is subscribed to the event' do
            it 'does not create a new notification for the target user' do
              expect { NotificationService::Notifier.new(event).call }.not_to change(Notification, :count)
            end
          end
        end

        context 'and the event triggers for a group' do
          let(:group) { create(:group_with_user) }
          let(:user) { group.users.first }
          let(:event) { Event::RelationshipDelete.create!(who: owner, group: group.title, package: package.name, project: project.name, notifiable_id: package.id) }

          context 'and a group is subscribed to the event' do
            before do
              event_subscription = create(
                :event_subscription,
                eventtype: 'Event::RelationshipDelete',
                receiver_role: 'any_role',
                user: user,
                group: nil,
                channel: :web
              )
              event_subscription.payload = { package: package.name }
            end

            it 'creates a new notification for the target user' do
              expect { NotificationService::Notifier.new(event).call }.to change(Notification, :count).to(1)
            end
          end

          context 'and no group is subscribed to the event' do
            it 'does not create a new notification for the target user' do
              expect { NotificationService::Notifier.new(event).call }.not_to change(Notification, :count)
            end
          end
        end
      end
    end
  end
end
