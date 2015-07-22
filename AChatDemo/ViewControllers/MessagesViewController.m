//
//  ViewController.m
//  smart-support-ios
//
//  Created by Alexandr Turyev on 11/07/15.
//  Copyright (c) 2015 Octoberry. All rights reserved.
//

#import "MessagesViewController.h"
#import "SharedEngine.h"
#import <JSQMessagesViewController/JSQMessages.h>
#import "AllyChatMessage.h"
#import "AllyChatUser.h"

#define STATUS_SENT @"Delivered"
#define STATUS_SENDING @"Sending..."
#define STATUS_ERROR @"Error"

#define MESSAGES_COUNT 5

@interface MessagesViewController ()

@property (nonatomic, strong) NSMutableArray *messages;

@property (nonatomic, strong) NSMutableDictionary *chatUsers;

@property (nonatomic, strong) JSQMessagesBubbleImage* outgoingBubbleImageData;
@property (nonatomic, strong) JSQMessagesBubbleImage* incomingBubbleImageData;

@end

@implementation MessagesViewController

#pragma mark AChat Delegate Methods

- (void)chat:(ACEngine *)engine didReceiveMessage:(ACMessageModel *)msgObject
{
    //Check if Message from current Room
    if ([msgObject.roomID isEqualToString:self.room.roomID])
    {
        //Outcomming message received
        if ([msgObject.senderID isEqualToString:self.senderId])
        {
            [self.messages enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                AllyChatMessage *message = obj;
                
                //Compare signature of received message with array of mesages
                if (([message.signature isEqualToString:msgObject.client_id]) && [message.status isEqualToString:STATUS_SENDING]) {
                    message.model = msgObject;
                    message.status = STATUS_SENT;
                    *stop = true;
                    [self finishReceivingMessageAnimated:YES];
                }
            }];
        }
        //Incomming message received
        else
        {
            [self addAllyChatMesage:msgObject];
            [self finishReceivingMessageAnimated:YES];
            
            //Mark it read
            [[SharedEngine shared].engine readMessage:msgObject.messageID completion:^(NSError *error, bool isComplete) {
                if (!isComplete) {
                    NSLog(@"%@", error);
                }
            }];
        }
    }
    else
    {
        //Show Message from another Room
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:msgObject.roomID message:msgObject.message delegate:nil cancelButtonTitle:@"Close" otherButtonTitles:nil, nil];
        [alertView show];
    }
}

-(void)chat:(ACEngine *)engine didConnectChatRoom:(ACRoomModel *)room
{
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:room.roomID message:room.lastMessage.message delegate:nil cancelButtonTitle:@"Close" otherButtonTitles:nil, nil];
    [alertView show];
}

#pragma mark - AChat methods

-(void)loadChatUser:(NSString *)senderId
{
    if (self.room.isSupportRoom)
    {
        [[SharedEngine shared].engine operatorById:senderId withCompletion:^(NSError *error, ACOperatorModel *operatorModel) {
            if (operatorModel) {
                AllyChatUser *chatUser = [AllyChatUser new];
                chatUser.userModel = operatorModel;
                self.chatUsers[senderId] = chatUser;
                [self.collectionView reloadData];
            }
        }];
    }
    else
    {
        [[SharedEngine shared].engine userWithId:senderId completion:^(NSError *error, ACUserModel *user) {
            AllyChatUser *chatUser = [AllyChatUser new];
            chatUser.userModel = user;
            self.chatUsers[senderId] = chatUser;
            [self.collectionView reloadData];
        }];
    }
}

-(void)addAllyChatMesage:(ACMessageModel *)messageModel
{
    AllyChatMessage *message = nil;
    
    AllyChatUser *user = self.chatUsers[messageModel.senderID];
    NSString *senderDisplayName = user?user.senderDisplayName:@"";
    
    if (messageModel.fileAttachmentURL)
    {
        JSQPhotoMediaItem *item = [JSQPhotoMediaItem new];
        message = [[AllyChatMessage alloc] initWithSenderId:messageModel.senderID senderDisplayName:senderDisplayName date:messageModel.sentDate media:item];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:messageModel.fileAttachmentURL]];
            item.image = [UIImage imageWithData:data];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.collectionView reloadData];
            });
        });
    }
    else
    {
        message = [[AllyChatMessage alloc] initWithSenderId:messageModel.senderID senderDisplayName:senderDisplayName date:messageModel.sentDate text:messageModel.message];
    }
    message.model = messageModel;
    message.status = STATUS_SENT;
    [self.messages addObject:message];
}

/**
 *  Load last Messages of the current Room
 */
-(void)loadLastMessages:(NSUInteger)count
{
    [[SharedEngine shared].engine lastMessages:@(count) roomId:self.room.roomID completion:^(NSError *error, NSArray *messages) {
        if (error == nil && messages) {
            if (messages.count>0) {
                for (ACMessageModel *messageModel in messages)
                {
                    [self addAllyChatMesage:messageModel];
                }
                [self finishReceivingMessageAnimated:YES];
            }
        }
    }];
}

/**
 *  Load earlier Messages (before Last One)
 */
-(void)loadEarlierMessages:(NSUInteger)count forLastMessage:(NSString *)messageId
{
    if (messageId) {
        [[SharedEngine shared].engine historyForRoomId:self.room.roomID limit:@(count) lastMessageID:messageId showNew:NO completion:^(NSError *error, NSArray *messages) {
            if (error == nil && messages) {
                if (messages.count>0)
                {
                    for (ACMessageModel *messageModel in messages)
                    {
                        [self addAllyChatMesage:messageModel];
                    }
                    [self.messages sortUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"date" ascending:YES]]];
                    [self.collectionView reloadData];
                }
            }
        }];
    }
}

- (void)messageSend:(NSString *)text
            picture:(UIImage *)picture
{
    
    AllyChatMessage *message = nil;
    
    //Create signature for Message
    NSString *uuid = [NSUUID UUID].UUIDString;
    
    if (picture) {
        JSQPhotoMediaItem *item = [[JSQPhotoMediaItem alloc] initWithImage:picture];
        message = [[AllyChatMessage alloc] initWithSenderId:self.senderId senderDisplayName:self.senderDisplayName date:[NSDate date] media:item];
        [[SharedEngine shared].engine sendImageMessage:picture roomId:self.room.roomID signature:uuid completion:^(NSError *error) {
            if (error) {
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error" message:error.localizedDescription delegate:nil cancelButtonTitle:@"CLose" otherButtonTitles:nil, nil];
                [alert show];
            }
            else
            {
                message.status = STATUS_SENT;
                [self finishSendingMessageAnimated:YES];
            }
        }];
    }
    else
    {
        message = [[AllyChatMessage alloc] initWithSenderId:self.senderId senderDisplayName:self.senderDisplayName date:[NSDate date] text:text];
        [[SharedEngine shared].engine sendTextMessage:text roomId:self.room.roomID signature:uuid completion:^(NSError *error) {
            if (error) {
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error" message:error.localizedDescription delegate:nil cancelButtonTitle:@"CLose" otherButtonTitles:nil, nil];
                [alert show];
            }
        }];
    }
    [JSQSystemSoundPlayer jsq_playMessageSentSound];
    message.signature = uuid;
    message.status = STATUS_SENDING;
    [self.messages addObject:message];
    [self finishSendingMessageAnimated:YES];
}

#pragma mark -


-(void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    self.collectionView.collectionViewLayout.springinessEnabled = NO;
    
}

- (void)viewDidLoad
{
    /**
     *  Handle all received messages
     */
    [SharedEngine shared].engine.delegate = self;
    
    /**
     *  Set properties correspond to determine which messages are incoming or outgoing.
     */
    self.senderId = [SharedEngine shared].engine.userModel.userID;
    self.senderDisplayName = [SharedEngine shared].engine.userModel.alias;

    /**
     *  Remove avatars for output messages
     */
    self.collectionView.collectionViewLayout.outgoingAvatarViewSize = CGSizeZero;
    
    JSQMessagesBubbleImageFactory *bubbleFactory = [[JSQMessagesBubbleImageFactory alloc] init];
    self.outgoingBubbleImageData = [bubbleFactory outgoingMessagesBubbleImageWithColor:[UIColor jsq_messageBubbleBlueColor]];
    self.incomingBubbleImageData = [bubbleFactory incomingMessagesBubbleImageWithColor:[UIColor jsq_messageBubbleLightGrayColor]];
    
    [super viewDidLoad];
    
    self.chatUsers = [NSMutableDictionary dictionary];
    self.messages = [NSMutableArray array];
    
    [self loadLastMessages:MESSAGES_COUNT];
    
    self.showLoadEarlierMessagesHeader = YES;
}

#pragma mark - JSQMessagesViewController method overrides

- (void)didPressSendButton:(UIButton *)button
           withMessageText:(NSString *)text
                  senderId:(NSString *)senderId
         senderDisplayName:(NSString *)senderDisplayName
                      date:(NSDate *)date
{
    [self messageSend:text picture:nil];
}

- (void)didPressAccessoryButton:(UIButton *)sender
{
    
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Media messages"
                                                       delegate:self
                                              cancelButtonTitle:@"Cancel"
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:@"Photo library", @"Camera", nil];
    
    [sheet showFromToolbar:self.inputToolbar];
}

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == actionSheet.cancelButtonIndex) {
        return;
    }
    
    int sourceType;
    if (buttonIndex == 0) {
        sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    } else {
        sourceType = UIImagePickerControllerSourceTypeCamera;
    }
    if (![UIImagePickerController isSourceTypeAvailable:sourceType])
    {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error" message:@"Current source is not available at this time" delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles:nil, nil];
        [alert show];
        return;
    }
    
    UIImagePickerController *imagePicker = [[UIImagePickerController alloc] init];
    imagePicker.delegate = self;
    
    imagePicker.sourceType = sourceType;
    imagePicker.allowsEditing = NO;
    if (imagePicker.sourceType == UIImagePickerControllerSourceTypeCamera) {
        imagePicker.showsCameraControls = YES;
    }
    [self presentViewController:imagePicker animated:YES completion:nil];
}

#pragma mark - JSQMessages CollectionView DataSource

- (id<JSQMessageData>)collectionView:(JSQMessagesCollectionView *)collectionView messageDataForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return [self.messages objectAtIndex:indexPath.item];
}

- (id<JSQMessageBubbleImageDataSource>)collectionView:(JSQMessagesCollectionView *)collectionView messageBubbleImageDataForItemAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self outgoing:self.messages[indexPath.item]])
    {
        return self.outgoingBubbleImageData;
    }
    else return self.incomingBubbleImageData;
}

- (id<JSQMessageAvatarImageDataSource>)collectionView:(JSQMessagesCollectionView *)collectionView avatarImageDataForItemAtIndexPath:(NSIndexPath *)indexPath
{
    AllyChatMessage *message = [self.messages objectAtIndex:indexPath.item];
    if ([self incoming:message])
    {
        if (self.chatUsers[message.senderId] == nil)
        {
            [self loadChatUser:message.senderId];
            return nil;
        }
        else return ((AllyChatUser *)self.chatUsers[message.senderId]).avatarImage;
    }
    else
        return nil;
}

- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView attributedTextForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.item % 3 == 0)
    {
        JSQMessage *message = self.messages[indexPath.item];
        return [[JSQMessagesTimestampFormatter sharedFormatter] attributedTimestampForDate:message.date];
    }
    else return nil;
}

- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView attributedTextForMessageBubbleTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    AllyChatMessage *message = [self.messages objectAtIndex:indexPath.item];
    if ([self incoming:message])
    {
        if (indexPath.item > 0)
        {
            JSQMessage *previous = self.messages[indexPath.item-1];
            if ([previous.senderId isEqualToString:message.senderId])
            {
                return nil;
            }
        }
        if (self.chatUsers[message.senderId] == nil)
        {
            [self loadChatUser:message.senderId];
            return nil;
        }
        else
        {
            NSString *name = ((AllyChatUser *)self.chatUsers[message.senderId]).senderDisplayName;
            return [[NSAttributedString alloc] initWithString:name];
        }
    }
    else return nil;
}

- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView attributedTextForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self outgoing:self.messages[indexPath.item]])
    {
       AllyChatMessage *message = [self.messages objectAtIndex:indexPath.item];
        return [[NSAttributedString alloc] initWithString:message.status];
    }
    else return nil;
}

#pragma mark - UICollectionView DataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return [self.messages count];
}

- (UICollectionViewCell *)collectionView:(JSQMessagesCollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    JSQMessagesCollectionViewCell *cell = (JSQMessagesCollectionViewCell *)[super collectionView:collectionView cellForItemAtIndexPath:indexPath];
    JSQMessage *msg = [self.messages objectAtIndex:indexPath.item];
    if (!msg.isMediaMessage) {
        
        if ([msg.senderId isEqualToString:self.senderId]) {
            cell.textView.textColor = [UIColor whiteColor];
            
        }
        else {
            cell.textView.textColor = [UIColor blackColor];
        }
        cell.textView.linkTextAttributes = @{ NSForegroundColorAttributeName : cell.textView.textColor,
                                              NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle | NSUnderlinePatternSolid) };
    }
    cell.cellBottomLabel.textInsets = UIEdgeInsetsMake(0.0, -kJSQMessagesCollectionViewAvatarSizeDefault , 0.0, 0.0);
    
    return cell;
}

#pragma mark - UICollectionView Delegate

#pragma mark - Adjusting cell label heights

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.item % 3 == 0) {
        return kJSQMessagesCollectionViewCellLabelHeightDefault;
    }
    
    return 0.0f;
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForMessageBubbleTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    JSQMessage *message = self.messages[indexPath.item];
    if ([self incoming:message])
    {
        if (indexPath.item > 0)
        {
            JSQMessage *previous = self.messages[indexPath.item-1];
            if ([previous.senderId isEqualToString:message.senderId])
            {
                return 0;
            }
        }
        return kJSQMessagesCollectionViewCellLabelHeightDefault;
    }
    else return 0;
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self outgoing:self.messages[indexPath.item]])
    {
        return kJSQMessagesCollectionViewCellLabelHeightDefault;
    }
    else return 0;
}

#pragma mark - Responding to collection view tap events

- (void)collectionView:(JSQMessagesCollectionView *)collectionView
                header:(JSQMessagesLoadEarlierHeaderView *)headerView didTapLoadEarlierMessagesButton:(UIButton *)sender
{
    AllyChatMessage *theOldestMessage = self.messages.firstObject;
    [self loadEarlierMessages:MESSAGES_COUNT forLastMessage:theOldestMessage.model.messageID];
}

#pragma mark - ImagePicker

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    
    UIImage *image = info[UIImagePickerControllerEditedImage];
    if (!image) {
        image = info[UIImagePickerControllerOriginalImage];
    }
    
    if (picker.sourceType == UIImagePickerControllerSourceTypeCamera) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil);
    }
    
    [self messageSend:nil picture:image];
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Helper methods

- (BOOL)incoming:(JSQMessage *)message
{
    return ([message.senderId isEqualToString:self.senderId] == NO);
}

- (BOOL)outgoing:(JSQMessage *)message
{
    return ([message.senderId isEqualToString:self.senderId] == YES);
}

@end